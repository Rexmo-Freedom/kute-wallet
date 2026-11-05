// A look by eye at the redesigned receipts, written only when asked:
// R4_RECEIPTS_RENDER=<dir> flutter test test/render/receipts_render_test.dart
// Six receipts (Lightning send, prediction sell, Investing reduce,
// Dollars deposit done and pending, on-chain receive) and one activity
// list (done, pending, in and out rows), light and dark, 390 x 844 at
// 3x, with the real Inter face and the shell bar over the sheet.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/hyperliquid_fill_activity.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/theme/app_theme.dart';

import '../screens/shared/receipt_fixtures.dart';

final _dir = Platform.environment['R4_RECEIPTS_RENDER'];

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final manifest = jsonDecode(
            await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
        as Map<String, dynamic>;
    SalSpriteCache.debugSetManifest(manifest);
    for (final clip in ['idle', 'search', 'share']) {
      await SalSpriteCache.clip(clip, 3);
    }
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

/// Opens one receipt over a plain page with the shell bar on top and
/// writes the screen to `<dir>/<name>.png`. [open] opens it from the
/// page's context; [home] replaces the page (a row to tap).
Future<void> _shot(WidgetTester tester, String name,
    {required bool dark,
    BaseTransaction? tx,
    Widget? home,
    String? tap}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  kuteShellMounted.value = true;
  addTearDown(() => kuteShellMounted.value = false);
  final key = GlobalKey();
  late BuildContext opener;
  late WidgetRef openerRef;
  final list = tx == null && tap == null;
  await tester.pumpWidget(receiptApp(
    home ??
        Consumer(builder: (context, ref, _) {
          opener = context;
          openerRef = ref;
          return ColoredBox(color: context.colors.background);
        }),
    theme: _theme(dark),
    builder: (context, child) => RepaintBoundary(
        key: key,
        child: Stack(children: [child!, const KuteShellBar()])),
  ));
  await tester.pump();
  if (tx != null) {
    await openTransactionDetails(opener, openerRef, tx);
  } else if (!list) {
    await tester.tap(find.text(tap!));
  }
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  Directory(_dir!).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // Let the network-backed parts (the flow graph's fetch) give up.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  late Directory hive;
  setUpAll(() async => hive = await openReceiptHive());
  tearDownAll(() => closeReceiptHive(hive));

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: Lightning send, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-lightning-send-$mode',
          dark: dark, tx: receiptLightningSend());
    });
    testWidgets('render: prediction sell, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-prediction-sell-$mode',
          dark: dark, tx: receiptPredictionSell());
    });
    testWidgets('render: Investing reduce, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-investing-reduce-$mode',
          dark: dark,
          home: Builder(
              builder: (context) => ColoredBox(
                  color: context.colors.background,
                  child: const Align(
                      alignment: Alignment.topCenter,
                      child: HyperliquidFillActivityRow(
                          fill: receiptInvestingReduce)))),
          tap: 'Reduced OAI');
    });
    testWidgets('render: Dollars deposit, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-dollars-deposit-$mode',
          dark: dark, tx: receiptDollarsDeposit());
    });
    testWidgets('render: Dollars deposit pending, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-dollars-deposit-pending-$mode',
          dark: dark, tx: receiptDollarsDeposit(pending: true));
    });
    testWidgets('render: activity list, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      final rows = <BaseTransaction>[
        receiptDollarsDeposit(pending: true),
        receiptOnChainReceive(confirmed: false),
        receiptDollarsDeposit(),
        receiptLightningSend(),
        receiptPredictionSell(),
        receiptOnChainReceive(),
      ];
      await _shot(tester, 'activity-list-$mode',
          dark: dark,
          home: Consumer(
              builder: (context, ref, _) => ColoredBox(
                  color: context.colors.background,
                  child: SafeArea(
                      child: Column(children: [
                    for (final tx in rows)
                      buildUnifiedTransactionItem(tx, context, ref),
                  ])))));
    });
    testWidgets('render: on-chain receive, $mode', skip: _dir == null,
        (tester) async {
      await _assets(tester);
      await _shot(tester, 'receipt-onchain-receive-$mode',
          dark: dark, tx: receiptOnChainReceive());
    });
  }
}
