// The share cards as images, for a look by eye, at 1080 × 1350 with Sal's
// real stills: bitcoin and dollars sends, a prediction
// pick, a prediction market, a stock pick (Tesla), a stock market (Nasdaq
// 100), oil, German and Japanese, and the claim heroes; then the phone screens
// that show them: Send to anyone's "Who is it for?" step with the live
// card, and the Claim screen. Every frame lays out without an overflow;
// the PNGs are written only when asked:
//
//   SHARE_CARD_FRAMES=<dir> flutter test test/screens/share/cards/share_card_render_test.dart
//
// Asked, the renders go to the network for what a real phone would load:
// the stocks' logos (HlCoinIcon) and two live Polymarket events (the
// esports "Worlds" winner market and a politics market, with their
// pictures and last week's chances), and, when they are on the board,
// the Brazil presidential and Michigan Senate markets with their real
// chart lines (the ranges a market chart opens on). Offline, the
// fixtures stand in.
// The Investing figures (Tesla, Nasdaq 100, oil) are made-up samples.
// SHARE_CARD_OFFLINE=1 writes them without the network (the fixtures).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider, polymarketMarketHistoryProvider;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/cards/share_cards.dart';
import 'package:kute/screens/share/claim_screen.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../helpers/kute_bar_test_support.dart';
import '../share_test_harness.dart';
import 'share_card_fixtures.dart';
import 'share_card_test_fonts.dart';
import '../share_artwork.dart';

/// Live Polymarket events for the renders (see the file header).
class _Live {
  final Map<String, PolymarketEvent> events = {};
  final Map<String, List<PolymarketPricePoint>> history = {};
  String? esports;
  String? politics;
  String? brazil;
  String? michigan;
}

/// The history ranges the live renders read: the pick card's week, and
/// the ranges a market chart may open on (polyChartAutoRange).
const Map<String, int> _kLiveRanges = {'1w': 60, '1m': 180, 'max': 720};

Future<Map<String, dynamic>?> _getJson(String url) async {
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    return decoded is List
        ? {'list': decoded}
        : decoded as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<_Live> _loadLive() async {
  final live = _Live();
  Future<String?> pick(String tag, bool Function(Map e) ok) async {
    // The keyset list (the offset `/events` list is sunset), as the app
    // reads it (PolymarketModel.fetchGammaKeyset).
    final j = await _getJson('https://gamma-api.polymarket.com/events/keyset'
        '?closed=false&order=volume24hr&ascending=false'
        '&limit=25&tag_slug=$tag');
    for (final e in (j?['events'] as List? ?? const [])) {
      if (e is Map && e['active'] == false) continue;
      if (e is Map && ok(e)) return e['slug'] as String?;
    }
    return null;
  }

  double lead(Map e) {
    var best = 0.0;
    for (final m in (e['markets'] as List? ?? const [])) {
      final p = m is Map ? m['outcomePrices'] : null;
      if (p is! String) continue;
      final v = double.tryParse((jsonDecode(p) as List).first.toString()) ?? 0;
      if (v > best) best = v;
    }
    return best;
  }

  live.esports = await pick(
      'esports',
      (e) =>
          '${e['title']}'.startsWith('Worlds') &&
          (e['markets'] as List).length > 2);
  live.politics = await pick('politics', (e) {
    final n = (e['markets'] as List).length;
    final l = lead(e);
    return n >= 2 && n <= 12 && l >= 0.3 && l <= 0.85;
  });
  // The founder's own examples, when they are on the board.
  live.brazil = await pick('politics', (e) {
        final t = '${e['title']}'.toLowerCase();
        return t.contains('brazil') && t.contains('presiden');
      }) ??
      // Off the open board once decided: the event by its slug.
      'brazil-presidential-election';
  live.michigan = await pick('politics', (e) {
    final t = '${e['title']}'.toLowerCase();
    return t.contains('michigan') && t.contains('senate');
  });
  final model = PolymarketModel();
  for (final slug in {live.esports, live.politics, live.brazil, live.michigan}
      .whereType<String>()) {
    final event = await model.getEventDetailsBySlug(slug);
    if (event == null) continue;
    live.events[slug] = event;
    // The most likely outcomes first: the lines a chart draws.
    final ranked = [...event.outcomes]
      ..sort((a, b) => b.price.compareTo(a.price));
    for (final o in ranked.take(4)) {
      final t = o.tokenId;
      if (t == null) continue;
      for (final MapEntry(key: range, value: fidelity)
          in _kLiveRanges.entries) {
        final points = await model
            .getPriceHistory(t, interval: range, fidelity: fidelity)
            .timeout(const Duration(seconds: 15), onTimeout: () => const []);
        if (points.isNotEmpty) live.history['$t|$range'] = points;
      }
    }
  }
  model.dispose();
  return live;
}

void main() {
  final dir = Platform.environment['SHARE_CARD_FRAMES'];

  Future<void> writePng(
      WidgetTester tester, RenderRepaintBoundary boundary, String name,
      {double ratio = kShareCardPixelRatio}) async {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir!).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  testWidgets('share cards render to PNG', (tester) async {
    await tester.runAsync(loadShareCardFonts);
    ShareCardSal.debugReset();
    addTearDown(ShareCardSal.debugReset);
    await tester.runAsync(loadShareCardSal);
    expect(ShareCardSal.peek(), isNotNull, reason: "Sal's face decodes");
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Live predictions when asked and reachable (see the file header).
    PredictionCardData pickCard = fakePredictionPick();
    PredictionCardData marketCard = fakePredictionMarket();
    PredictionCardData brazilCard = fakePredictionMarket();
    PredictionCardData michiganCard = fakeMichiganMarket();
    if (dir != null && Platform.environment['SHARE_CARD_OFFLINE'] == null) {
      HttpOverrides.global = null;
      useShareTestArtwork(online: true);
      final live = await tester.runAsync(_loadLive);
      if (live != null && live.events.isNotEmpty) {
        final container = ProviderContainer(overrides: [
          polymarketEventDetailsProvider
              .overrideWith((ref, slug) async => live.events[slug]),
          polymarketMarketHistoryProvider.overrideWith((ref, key) async =>
              live.history['${key.tokenId}|${key.interval}'] ?? const []),
        ]);
        addTearDown(container.dispose);
        Future<void> warm(String slug) async {
          await container.read(polymarketEventDetailsProvider(slug).future);
          for (final PolymarketOutcome o
              in live.events[slug]?.outcomes ?? const []) {
            final t = o.tokenId;
            if (t == null) continue;
            for (final range in _kLiveRanges.keys) {
              final key = (tokenId: t, interval: range);
              container.listen(
                  polymarketMarketHistoryProvider(key), (_, __) {});
              await container
                  .read(polymarketMarketHistoryProvider(key).future);
            }
          }
        }

        T watch<T>(ProviderListenable<T> p) => container.read(p);
        final e = live.esports;
        if (e != null && live.events.containsKey(e)) {
          container.listen(polymarketEventDetailsProvider(e), (_, __) {});
          await tester.runAsync(() => warm(e));
          pickCard = predictionCardFor(watch,
              slug: e,
              title: '',
              picked: true,
              amount: r'$10',
              recipient: 'Ana',
              referralCode: kShareTestCode);
        }
        final p = live.politics;
        if (p != null && live.events.containsKey(p)) {
          container.listen(polymarketEventDetailsProvider(p), (_, __) {});
          await tester.runAsync(() => warm(p));
          marketCard = predictionCardFor(watch,
              slug: p, title: '', referralCode: kShareTestCode);
        }
        for (final (slug, set) in [
          (live.brazil, (PredictionCardData c) => brazilCard = c),
          (live.michigan, (PredictionCardData c) => michiganCard = c),
        ]) {
          if (slug == null || !live.events.containsKey(slug)) continue;
          container.listen(polymarketEventDetailsProvider(slug), (_, __) {});
          await tester.runAsync(() => warm(slug));
          set(predictionCardFor(watch,
              slug: slug, title: '', referralCode: kShareTestCode));
        }
      }
    }

    final frames = <String, (ShareCardData, Locale)>{
      '1_send_bitcoin': (fakeBitcoinCard(), const Locale('en')),
      '1_send_dollars': (fakeDollarsCard(), const Locale('en')),
      '2_send_prediction': (pickCard, const Locale('en')),
      '3_send_stock_tesla': (fakeTeslaPick(), const Locale('en')),
      '3_market_nasdaq100': (fakeNasdaqMarket(), const Locale('en')),
      '3_market_crude_oil': (fakeOilMarket(), const Locale('en')),
      '4_market_prediction': (marketCard, const Locale('en')),
      'de_send_stock_tesla': (fakeTeslaPick(), const Locale('de')),
      'de_send_bitcoin': (fakeBitcoinCard(), const Locale('de')),
      'de_send_prediction': (pickCard, const Locale('de')),
      'ja_send_prediction': (pickCard, const Locale('ja')),
      // Long titles (founder, 2 November 2026: "try to not cut titles").
      '5_pick_long_question':
          (fakePredictionPick(question: kShareLongQuestion), const Locale('en')),
      'de_pick_long_question':
          (fakePredictionPick(question: kShareLongQuestion), const Locale('de')),
      'ja_pick_long_question':
          (fakePredictionPick(question: kShareLongQuestion), const Locale('ja')),
      '5_pick_btc_150k': (fakeBinaryPick(), const Locale('en')),
      'de_pick_btc_150k': (fakeBinaryPick(), const Locale('de')),
      '6_market_brazil': (brazilCard, const Locale('en')),
      'de_market_brazil': (brazilCard, const Locale('de')),
      'ja_market_brazil': (brazilCard, const Locale('ja')),
      '6_market_michigan': (michiganCard, const Locale('en')),
      'de_market_michigan': (michiganCard, const Locale('de')),
      // No history read yet: the speedometer, never a made-up line.
      '6_market_brazil_no_history':
          (fakePredictionMarket(chart: false), const Locale('en')),
      'claim_hero_bitcoin': (
        const MoneyCardData(
            bitcoin: true,
            amount: '₿12,000',
            amountSub: r'$9.40',
            recipient: 'Daniel',
            audience: ShareCardAudience.recipient),
        const Locale('en')
      ),
      'claim_hero_prediction': (
        fakePredictionPick(name: 'Daniel').asRecipient(),
        const Locale('en')
      ),
    };
    for (final MapEntry(key: name, value: (data, locale)) in frames.entries) {
      final key = GlobalKey();
      final app = ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: ShareCard(data: data, mark: ShareCardSal.peek()),
                  ),
                ),
              ));
      if (dir == null) {
        await tester.pumpWidget(app);
      } else {
        // Built on real time so the logos and pictures load over the
        // network (see the file header).
        await tester.runAsync(() async {
          await tester.pumpWidget(app);
          await Future<void>.delayed(const Duration(seconds: 4));
          // The artwork resolved: its image decodes on real time too.
          await tester.pump();
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final error = tester.takeException();
      expect(error, isNull, reason: '$name overflowed: $error');
      if (dir == null) continue;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await writePng(tester, boundary, name);
    }
    // The logo fetches' timeouts, run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  group('screens', () {
    late ShareTestEnv env;
    setUp(() {
      env = setUpShareTest();
      WidgetsApp.debugAllowBannerOverride = false;
    });
    tearDown(() {
      tearDownShareTest();
      WidgetsApp.debugAllowBannerOverride = true;
    });

    // The whole view, the shell bar (the screens' primary button) too.
    Future<void> capture(WidgetTester tester, String name) async {
      final error = tester.takeException();
      expect(error, isNull, reason: '$name overflowed: $error');
      if (dir == null) return;
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final image =
            await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(dir).createSync(recursive: true);
        File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    Widget framed(Widget child) => child;

    testWidgets('Who is it for? with the live card', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      await tester.runAsync(loadShareCardSal);
      await pumpShareWidget(
          tester,
          env,
          framed(const SendToAnyoneSheet(
              kind: ShareLinkKind.dollars, senderLabel: 'Daniel')));
      for (final k in ['5', '0']) {
        await tester.tap(find.text(k));
        await tester.pump();
      }
      await settle(tester);
      await tester.tap(kuteBarPrimaryWithText('Continue'));
      await settle(tester);
      expect(find.text('FOR DANIEL'), findsOneWidget);
      await capture(tester, 'screen_who_is_it_for');
    });

    testWidgets('Claim screen hero', (tester) async {
      await tester.runAsync(loadShareCardFonts);
      await tester.runAsync(loadShareCardSal);
      ClaimScreen.debugDestination = (_) async => 'spark1recipient';
      addTearDown(() => ClaimScreen.debugDestination = null);
      env.fake.seed(ShareLink(
        id: 'lnk_1',
        kind: ShareLinkKind.dollars,
        amountMinor: 5000,
        senderLabel: 'Daniel',
        status: ShareLinkStatus.open,
        rawStatus: 'open',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      ));
      await pumpShareWidget(
          tester, env, framed(const ClaimScreen(id: 'lnk_1')));
      expect(find.text('DANIEL, A FRIEND SENT YOU'), findsOneWidget);
      await capture(tester, 'screen_claim');
    });
  });
}
