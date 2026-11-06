// The Receive button's glyph on the Bitcoin and Dollars rows (founder, 6
// November 2026): the receive arrow with a small swap badge at its lower
// right, drawn in code ([ReceiveSwapGlyph]), because the sheet behind the
// button is "Receive or swap". The label stays "Receive", the tracking id
// stays `receive`, and the glyph wears the same colour and size as the
// other action icons in light and dark. A watch-only wallet, offered no
// swap, keeps the plain arrow.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/receive/receive_sheet.dart' show ReceiveSheets;
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart'
    show bitcoinWalletDockActions;
import 'package:kute/screens/shared/receive_swap_glyph.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _cold = WalletConfig(
    id: 'cold', name: 'Cold', isWatchOnly: true, sparkEnabled: false);

Future<void> _pump(WidgetTester tester, Widget body,
    {bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [_spending, _cold],
          ))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: body)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The Bitcoin home row's Receive and Send, then the Dollars row.
Widget _rows(WalletConfig wallet) => Consumer(
      builder: (context, ref, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KuteCompactActions(
              key: const ValueKey('bitcoin-row'),
              source: 'home',
              actions: bitcoinWalletDockActions(context, ref, wallet)),
          const SizedBox(height: 24),
          const UsdAccountActionRow(key: ValueKey('dollars-row')),
        ],
      ),
    );

Finder _in(String row, Finder f) =>
    find.descendant(of: find.byKey(ValueKey(row)), matching: f);

/// The alpha of the pixel at ([x], [y]) of [bytes], a [width]-wide RGBA.
int _alpha(ByteData bytes, int width, int x, int y) =>
    bytes.getUint8((y * width + x) * 4 + 3);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
        '$mode: Receive on the Bitcoin and Dollars rows is the arrow with '
        'the swap badge, labelled Receive, in the Send arrow\'s colour and '
        'size, centred where the Send arrow is', (tester) async {
      await _pump(tester, _rows(_spending), dark: dark);
      final colors = tester.element(find.byType(UsdAccountActionRow)).colors;
      for (final row in ['bitcoin-row', 'dollars-row']) {
        final glyph = _in(row, find.byType(ReceiveSwapGlyph));
        expect(glyph, findsOneWidget, reason: row);
        expect(_in(row, find.byIcon(Icons.south_west_rounded)), findsNothing,
            reason: row);
        expect(_in(row, find.text('Receive')), findsOneWidget, reason: row);
        final send =
            tester.widget<Icon>(_in(row, find.byIcon(Icons.north_east_rounded)));
        final drawn = tester.widget<ReceiveSwapGlyph>(glyph);
        expect(drawn.color, send.color, reason: row);
        expect(drawn.color, colors.textPrimary, reason: row);
        expect(drawn.size, send.size, reason: row);
        // It takes the square's room as the Icon does, and draws the
        // icon's size in its centre.
        final sendBox = _in(row, find.byIcon(Icons.north_east_rounded));
        expect(tester.getSize(glyph), tester.getSize(sendBox), reason: row);
        expect(
            tester.getSize(find.descendant(
                of: glyph, matching: find.byType(CustomPaint))),
            Size.square(send.size!),
            reason: row);
        expect(tester.getCenter(glyph).dy,
            moreOrLessEquals(tester.getCenter(sendBox).dy),
            reason: row);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a tap keeps the action id `receive` on both rows, and opens Receive '
      'or swap', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    ReceiveSheets.debugBitcoinOptionsBody = (_) => const Text('options');
    addTearDown(() => ReceiveSheets.debugBitcoinOptionsBody = null);
    var dollarsOpened = 0;
    UsdAccountActionBar.debugReceiveOpener = (_) => dollarsOpened++;
    addTearDown(() => UsdAccountActionBar.debugReceiveOpener = null);
    await _pump(tester, _rows(_spending));

    await tester.tap(_in('dollars-row', find.byType(ReceiveSwapGlyph)));
    await tester.pump();
    expect(dollarsOpened, 1);
    await tester.tap(_in('bitcoin-row', find.byType(ReceiveSwapGlyph)));
    await tester.pumpAndSettle();
    expect(find.text('options'), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'quick_action_tapped').map((e) => e.$2), [
      {'action': 'receive', 'source': 'usd'},
      {'action': 'receive', 'source': 'home'},
    ]);
  });

  testWidgets(
      'a watch-only wallet, offered no swap, keeps the plain arrow; the '
      'Dollars row still wears the badge', (tester) async {
    await _pump(tester, _rows(_cold));
    expect(_in('bitcoin-row', find.byType(ReceiveSwapGlyph)), findsNothing);
    expect(_in('bitcoin-row', find.byIcon(Icons.south_west_rounded)),
        findsOneWidget);
    expect(_in('dollars-row', find.byType(ReceiveSwapGlyph)), findsOneWidget);
  });

  testWidgets(
      'the dock button draws the glyph too, in its icon colour and size',
      (tester) async {
    await _pump(
        tester,
        Consumer(
            builder: (context, ref, _) => KuteActionRow(
                source: 'home',
                actions: bitcoinWalletDockActions(context, ref, _spending))));
    final send = tester.widget<Icon>(find.byIcon(Icons.north_east_rounded));
    final glyph =
        tester.widget<ReceiveSwapGlyph>(find.byType(ReceiveSwapGlyph));
    expect(glyph.color, send.color);
    expect(glyph.size, send.size);
    expect(find.byIcon(Icons.south_west_rounded), findsNothing);
  });

  testWidgets(
      'the drawing: the arrow and a solid badge with the swap knocked out '
      'and a clear ring round it, in any colour, at 1x, 2x and 3x',
      (tester) async {
    for (final colour in [Colors.black, Colors.white]) {
      for (final ratio in [1.0, 2.0, 3.0]) {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('glyph'),
              child: ReceiveSwapGlyph(color: colour, size: 48),
            ),
          ),
        ));
        expect(tester.getSize(find.byType(ReceiveSwapGlyph)),
            const Size.square(48));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('glyph')));
        final image =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
        final bytes = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        final width = image.width;
        expect(width, (48 * ratio).round());
        // Grid units (24) to image pixels.
        int at(double u) => (u * 2 * ratio).floor();
        final why = '$colour at ${ratio}x';
        // The arrow's corner and its shaft's middle are ink.
        expect(_alpha(bytes, width, at(5), at(15.5)), greaterThan(200),
            reason: '$why: the arrow corner');
        expect(_alpha(bytes, width, at(10.5), at(10)), greaterThan(200),
            reason: '$why: the arrow shaft');
        // The badge: solid at its middle, between the two swap lines...
        expect(_alpha(bytes, width, at(19), at(19)), greaterThan(200),
            reason: '$why: the badge');
        // ...the lines themselves knocked out to the square behind...
        expect(_alpha(bytes, width, at(19), at(17.6)), lessThan(40),
            reason: '$why: the upper swap line');
        expect(_alpha(bytes, width, at(19), at(20.4)), lessThan(40),
            reason: '$why: the lower swap line');
        // ...and the ring round the badge clear.
        expect(_alpha(bytes, width, at(19 - 5.75), at(19)), lessThan(40),
            reason: '$why: the ring');
        // Nothing at the top right corner.
        expect(_alpha(bytes, width, at(22), at(2)), 0,
            reason: '$why: the corner');
        image.dispose();
      }
    }
    expect(tester.takeException(), isNull);
  });

  test('repaints only for a new colour', () {
    const a = ReceiveSwapGlyphPainter(Colors.black);
    expect(a.shouldRepaint(const ReceiveSwapGlyphPainter(Colors.black)),
        isFalse);
    expect(a.shouldRepaint(const ReceiveSwapGlyphPainter(Colors.white)),
        isTrue);
  });
}
