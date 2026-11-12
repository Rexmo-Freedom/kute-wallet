// Render harness for the live round card, whose buttons bet only on the
// next round (founder, 12 November 2026): the compact and full card with
// the next round priced and without prices yet, light and dark, at 320 and
// 375 wide, long locales, and the slip on the next round, in the app's
// real themes and Inter. Writes PNGs.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/next_round_render_test.dart \
//     --dart-define=NEXT_ROUND_OUT=/tmp/next-round

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

import '../helpers/shell_bar_harness.dart';
import '../screens/polymarket/crypto_next_round_card_test.dart' as card;

const _out = String.fromEnvironment('NEXT_ROUND_OUT');
const _key = ValueKey('shot');

Future<void> _shot(WidgetTester tester, String name,
    {required card.CardWorld world,
    required Size size,
    bool compact = true,
    bool dark = false,
    Locale? locale,
    bool priced = true,
    bool slip = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  world.now = card.roundStart.add(const Duration(minutes: 2, seconds: 44));
  world.listNext(quoted: priced);
  world.quoteCurrent();
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: ProviderScope(
      overrides: world.overrides(),
      child: shellBarApp(
        dark: dark,
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: CryptoPredictBanner(
                    key: const ValueKey('card'),
                    config: kCryptoPredictAssets.first,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  if (slip) {
    await tester.tap(find.byKey(const ValueKey('crypto-round-up')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    expect(find.byType(BetSlipSheet), findsOneWidget);
  }
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image =
      (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  await tester.runAsync(() async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
}

void main() {
  if (_out.isEmpty) {
    test('next round render', () {},
        skip: 'on demand: --dart-define=NEXT_ROUND_OUT=<dir>');
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
    for (final (w, f) in [
      (FontWeight.w400, 'Regular'),
      (FontWeight.w500, 'Regular'),
      (FontWeight.w600, 'SemiBold'),
      (FontWeight.w700, 'Bold'),
      (FontWeight.w800, 'Bold'),
    ]) {
      await (FontLoader(GoogleFonts.inter(fontWeight: w).fontFamily!)
            ..addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf')))
          .load();
    }
  });

  late card.CardWorld world;
  setUp(() {
    world = card.CardWorld()..install();
    BetSlipSheet.debugClock = () => world.now;
    installShellBar();
  });
  tearDown(() {
    BetSlipSheet.debugClock = DateTime.now;
    PolymarketLiveBooks.instance.reset();
  });

  for (final (w, h) in [(320.0, 568.0), (375.0, 812.0)]) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      for (final priced in [false, true]) {
        final state = priced ? 'next' : 'no-prices';
        testWidgets('compact $state $theme ${w.toInt()}', (tester) => _shot(
            tester, 'compact-$state-$theme-${w.toInt()}',
            world: world, size: Size(w, h), dark: dark, priced: priced));
        testWidgets('full $state $theme ${w.toInt()}', (tester) => _shot(
            tester, 'full-$state-$theme-${w.toInt()}',
            world: world,
            size: Size(w, h),
            dark: dark,
            priced: priced,
            compact: false));
      }
    }
  }
  for (final code in ['hu', 'ro', 'de', 'ja']) {
    testWidgets('compact next $code 320', (tester) => _shot(
        tester, 'compact-next-$code-320',
        world: world,
        size: const Size(320, 568),
        locale: Locale(code)));
  }
  testWidgets('full next hu 320', (tester) => _shot(tester, 'full-next-hu-320',
      world: world,
      size: const Size(320, 568),
      compact: false,
      locale: const Locale('hu')));
  for (final dark in [false, true]) {
    testWidgets('slip on next ${dark ? 'dark' : 'light'}', (tester) => _shot(
        tester, 'slip-next-${dark ? 'dark' : 'light'}-375',
        world: world,
        size: const Size(375, 812),
        dark: dark,
        slip: true));
  }
  testWidgets('slip on next hu 320', (tester) => _shot(tester, 'slip-next-hu-320',
      world: world,
      size: const Size(320, 568),
      slip: true,
      locale: const Locale('hu')));
}
