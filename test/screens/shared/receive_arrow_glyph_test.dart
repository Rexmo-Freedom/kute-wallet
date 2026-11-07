// The Receive button's glyph on the Bitcoin and Dollars rows and the
// docks (founder, 7 November 2026): the plain receive arrow (the swap
// badge went with the word swap), moving the way the hub's "+ with a
// gear" moves ([ReceiveArrowGlyph]): a short beat when it appears and
// every nine seconds, the arrow travelling in along its own line and
// back; a quick nudge on each press anywhere on its button; still under
// Reduce Motion. The label stays "Receive", the tracking id `receive`, and
// at rest the glyph is exactly the arrow icon, in the Send arrow's colour
// and size.

import 'package:flutter/material.dart';
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
import 'package:kute/screens/shared/receive_arrow_glyph.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _cold = WalletConfig(
    id: 'cold', name: 'Cold', isWatchOnly: true, sparkEnabled: false);

Future<void> _pump(WidgetTester tester, Widget body,
    {bool dark = false, bool reduceMotion = false}) async {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
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

/// How far in [glyph]'s arrow is drawn now, in pixels, as (dx, dy).
Offset _offset(WidgetTester tester, Finder glyph) {
  final transforms =
      find.descendant(of: glyph, matching: find.byType(Transform));
  if (transforms.evaluate().isEmpty) return Offset.zero;
  final t = tester.widget<Transform>(transforms.first).transform;
  final v = t.getTranslation();
  return Offset(v.x, v.y);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
        '$mode: Receive on the Bitcoin and Dollars rows is the plain arrow, '
        'labelled Receive, in the Send arrow\'s colour and size, centred '
        'where the Send arrow is; no swap badge', (tester) async {
      await _pump(tester, _rows(_spending), dark: dark);
      final colors = tester.element(find.byType(UsdAccountActionRow)).colors;
      for (final row in ['bitcoin-row', 'dollars-row']) {
        final glyph = _in(row, find.byType(ReceiveArrowGlyph));
        expect(glyph, findsOneWidget, reason: row);
        expect(_in(row, find.text('Receive')), findsOneWidget, reason: row);
        final arrow = tester.widget<Icon>(find.descendant(
            of: glyph, matching: find.byIcon(Icons.south_west_rounded)));
        final send =
            tester.widget<Icon>(_in(row, find.byIcon(Icons.north_east_rounded)));
        expect(arrow.color, send.color, reason: row);
        expect(arrow.color, colors.textPrimary, reason: row);
        expect(arrow.size, send.size, reason: row);
        // Nothing drawn in code beside the icon: the badge is gone.
        expect(find.descendant(of: glyph, matching: find.byType(CustomPaint)),
            findsNothing,
            reason: row);
        // At rest, exactly where the Send arrow sits.
        expect(_offset(tester, glyph), Offset.zero, reason: row);
        expect(
            tester.getCenter(glyph).dy,
            moreOrLessEquals(tester
                .getCenter(_in(row, find.byIcon(Icons.north_east_rounded)))
                .dy),
            reason: row);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a tap keeps the action id `receive` on both rows, and opens Receive',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    ReceiveSheets.debugBitcoinOptionsBody = (_) => const Text('options');
    addTearDown(() => ReceiveSheets.debugBitcoinOptionsBody = null);
    var dollarsOpened = 0;
    UsdAccountActionBar.debugReceiveOpener = (_) => dollarsOpened++;
    addTearDown(() => UsdAccountActionBar.debugReceiveOpener = null);
    await _pump(tester, _rows(_spending));

    await tester.tap(_in('dollars-row', find.byType(ReceiveArrowGlyph)));
    await tester.pump();
    expect(dollarsOpened, 1);
    await tester.tap(_in('bitcoin-row', find.byType(ReceiveArrowGlyph)));
    await tester.pumpAndSettle();
    expect(find.text('options'), findsOneWidget);
    expect(
        events.where((e) => e.$1 == 'quick_action_tapped').map((e) => e.$2), [
      {'action': 'receive', 'source': 'usd'},
      {'action': 'receive', 'source': 'home'},
    ]);
  });

  testWidgets(
      'a watch-only wallet wears the same arrow (it opens the QR itself)',
      (tester) async {
    await _pump(tester, _rows(_cold));
    expect(_in('bitcoin-row', find.byType(ReceiveArrowGlyph)), findsOneWidget);
    expect(_in('bitcoin-row', find.byIcon(Icons.south_west_rounded)),
        findsOneWidget);
    expect(_in('dollars-row', find.byType(ReceiveArrowGlyph)), findsOneWidget);
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
        tester.widget<ReceiveArrowGlyph>(find.byType(ReceiveArrowGlyph));
    expect(glyph.color, send.color);
    expect(glyph.size, send.size);
  });

  test('the beat: in along the arrow\'s own line, held, back to rest', () {
    const inEnd = kReceiveArrowInEnd, outStart = kReceiveArrowOutStart;
    expect(receiveArrowNudge(0, inEnd, outStart), 0);
    expect(receiveArrowNudge(inEnd / 2, inEnd, outStart), closeTo(0.5, 0.01));
    expect(receiveArrowNudge((inEnd + outStart) / 2, inEnd, outStart), 1);
    expect(receiveArrowNudge(1, inEnd, outStart), 0);
    // Down and to the left, three units of the 24 grid along the diagonal.
    final o = receiveArrowOffset(1, 24);
    expect(o.dx, lessThan(0));
    expect(o.dy, greaterThan(0));
    expect(o.distance, closeTo(kReceiveArrowTravel, 1e-9));
    expect(receiveArrowOffset(1, 48).distance,
        closeTo(2 * kReceiveArrowTravel, 1e-9));
    expect(receiveArrowOffset(0, 24), Offset.zero);
  });

  testWidgets(
      'it plays when it appears: in, held, back to rest; then once again '
      'after the rest between plays, nothing ticking in between',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: ReceiveArrowGlyph(
                color: Colors.black,
                size: 24,
                interval: Duration(seconds: 9)))));
    final glyph = find.byType(ReceiveArrowGlyph);
    final full = receiveArrowOffset(1, 24);
    // Held at the top of the beat.
    await tester.pump(const Duration(milliseconds: 800));
    expect(_offset(tester, glyph).dx, moreOrLessEquals(full.dx));
    expect(_offset(tester, glyph).dy, moreOrLessEquals(full.dy));
    // Back at rest once the beat ends, and still while it rests.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_offset(tester, glyph), Offset.zero);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(_offset(tester, glyph), Offset.zero);
    expect(tester.hasRunningAnimations, isFalse);
    // The next beat.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 800));
    expect(_offset(tester, glyph).dx, moreOrLessEquals(full.dx));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a press anywhere on the button plays the quick nudge, the hub\'s '
      'press', (tester) async {
    ReceiveSheets.debugBitcoinOptionsBody = (_) => const Text('options');
    addTearDown(() => ReceiveSheets.debugBitcoinOptionsBody = null);
    await _pump(tester, _rows(_spending));
    final glyph = _in('bitcoin-row', find.byType(ReceiveArrowGlyph));
    expect(_offset(tester, glyph), Offset.zero);
    // On the label, outside the glyph's own box.
    final press = await tester.startGesture(
        tester.getCenter(_in('bitcoin-row', find.text('Receive'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final o = _offset(tester, glyph);
    expect(o.dx, lessThan(0));
    expect(o.dy, greaterThan(0));
    expect(o.distance,
        moreOrLessEquals(receiveArrowOffset(1, 22).distance, epsilon: 0.01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_offset(tester, glyph), Offset.zero);
    await press.cancel();
    await tester.pumpAndSettle();
    // The Dollars row's Receive presses the same way.
    final dollars = _in('dollars-row', find.byType(ReceiveArrowGlyph));
    final second = await tester.startGesture(tester.getCenter(dollars));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(_offset(tester, dollars).distance, greaterThan(0));
    await second.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Reduce Motion: the plain arrow, still for good, appearing or pressed',
      (tester) async {
    await _pump(tester, _rows(_spending), reduceMotion: true);
    final glyph = _in('bitcoin-row', find.byType(ReceiveArrowGlyph));
    expect(find.descendant(of: glyph, matching: find.byType(Transform)),
        findsNothing);
    expect(find.descendant(of: glyph, matching: find.byType(AnimatedBuilder)),
        findsNothing);
    final press = await tester.startGesture(tester.getCenter(glyph));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(_offset(tester, glyph), Offset.zero);
    await press.cancel();
    await tester.pumpAndSettle();
  });
}
