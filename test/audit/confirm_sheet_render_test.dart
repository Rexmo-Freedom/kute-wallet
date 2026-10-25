// Result sheet render harness: presents the shared result sheet
// (KuteConfirmation) over a stand-in screen in its main states, light and
// dark, and writes each as a PNG; then a strip of Sal's tail-wag frames,
// to check the tail visibly swings. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/confirm_sheet_render_test.dart \
//     --dart-define=CONFIRM_SHEET_RENDER=true \
//     --dart-define=CONFIRM_SHEET_RENDER_OUT=/tmp/kute_confirm_sheet

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('CONFIRM_SHEET_RENDER');
const _outDefine = String.fromEnvironment('CONFIRM_SHEET_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_confirm_sheet';

const _shotKey = ValueKey('confirm-sheet-render-shot');

/// A plain screen with a balance and a few rows, so the scrim has
/// something to dim.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spending', style: AppTextStyles.bodySmall(context)),
              const SizedBox(height: 6),
              Text(r'$1,284.20', style: AppTextStyles.balance(context)),
              const SizedBox(height: 28),
              for (var i = 0; i < 6; i++)
                Container(
                  height: 64,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<NavigatorState> _host(WidgetTester tester, {required bool dark}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      navigatorKey: key,
      debugShowCheckedModeBanner: false,
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => RepaintBoundary(key: _shotKey, child: child),
      home: const _Backdrop(),
    ),
  ));
  await tester.pump();
  return key.currentState!;
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
  print('RENDER wrote $_out/$name.png');
}

/// The states worth looking at, by name.
Map<String, KuteConfirmation> _states(NavigatorState nav) => {
      'sent': KuteConfirmation(
        message: 'Bitcoin sent',
        amount: '25,000 sats',
        contextLine: 'To bc1qxy2k…0wlh',
        rows: const {'Network fee': '312 sats', 'Arrives': '~10 min'},
        transaction: TradeReceiptTransaction.bitcoin(
            'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'),
        onDone: nav.pop,
      ),
      'bet_placed': KuteConfirmation(
        message: 'Prediction placed',
        amount: r'$5.00 on Yes',
        contextLine: 'Will Bitcoin close above \$120k on Friday?',
        rows: const {'Shares': '8.33', 'Pays if right': r'$8.33'},
        secondaryButtonText: 'View prediction',
        onSecondary: nav.pop,
        onDone: nav.pop,
      ),
      'order_resting': KuteConfirmation(
        tone: KuteConfirmationTone.pending,
        message: r'Order placed · waits for 42¢',
        amount: r'$10.00 on No',
        contextLine: 'Fed cuts rates in December?',
        rows: const {'Limit price': '42¢', 'Shares': '23.81'},
        secondaryButtonText: 'View orders',
        onSecondary: nav.pop,
        onDone: nav.pop,
      ),
      'failure': KuteConfirmation(
        tone: KuteConfirmationTone.failure,
        message: "Couldn't send",
        amount: '25,000 sats',
        contextLine: 'Nothing left your wallet. Your balance is unchanged.',
        buttonText: 'Try again',
        onDone: nav.pop,
      ),
      'win': KuteConfirmation(
        tone: KuteConfirmationTone.celebrate,
        message: 'Winnings claimed',
        amount: r'$42.50',
        contextLine: 'Yes · Will it rain in London tomorrow?',
        rows: const {'Destination': 'Predictions balance', 'Network fee': 'Free'},
        onDone: nav.pop,
      ),
    };

void main() {
  if (!_enabled) {
    test('confirm sheet render', () {},
        skip: 'on demand: --dart-define=CONFIRM_SHEET_RENDER=true');
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
    KuteConfirmation.debugFeedbackOverride = () async {};
    KuteConfirmation.debugFailureFeedbackOverride = () async {};
  });

  for (final dark in [false, true]) {
    for (final name in [
      'sent',
      'bet_placed',
      'order_resting',
      'failure',
      'win'
    ]) {
      testWidgets('$name ${dark ? 'dark' : 'light'}', (tester) async {
        final nav = await _host(tester, dark: dark);
        pushKuteSuccessOverlay(navigator: nav, overlay: _states(nav)[name]!);
        // Slide (320) + check (580) + a moment of Sal's reaction.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _shot(tester, '${name}_${dark ? 'dark' : 'light'}');
        nav.pop();
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('sal wag frames', (tester) async {
    tester.view.physicalSize = const Size(600, 140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Quarter periods of the 190 ms wag: the swing's extremes.
    const frames = [0.0, 237.5, 332.5, 427.5, 522.5, 1500.0];
    await tester.pumpWidget(RepaintBoundary(
      key: _shotKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Row(children: [
            for (final ms in frames)
              Padding(
                padding: const EdgeInsets.all(10),
                child: CustomPaint(
                  size: const Size.square(80),
                  painter: KuteDogPainter(
                    pose: KuteDogConfirmation.poseAt(KuteDogMood.happy, ms),
                    palette: KuteDogPalette.mascot,
                  ),
                ),
              ),
          ]),
        ),
      ),
    ));
    await _shot(tester, 'sal_wag_frames');
  });
}
