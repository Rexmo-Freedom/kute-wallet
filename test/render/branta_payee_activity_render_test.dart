// A look by eye at the Bitcoin home's Activity with a send whose payee
// Branta verified (founder, 12 November 2026; branta_payee_records.dart),
// light and dark, written only when asked: BRANTA_ACTIVITY_RENDER=<dir>.
// The payee is Branta's own staging sample ("Branta"), its logo read from
// SEND_BRANTA_LOGO=<png> when given, else a plain painted mark. Its Latest
// square wears the logo in the row's circle and reads "Sent to Branta";
// the other rows look as they always did.
//
//   BRANTA_ACTIVITY_RENDER=<dir> flutter test \
//     test/render/branta_payee_activity_render_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/send/send_branta_payee.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityRowStyle;
import 'package:kute/services/branta/branta_payee_records.dart';
import 'package:kute/services/branta/branta_payee_service.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/offline_venue_overrides.dart';
import '../helpers/portfolio_overrides.dart';

final _dir = Platform.environment['BRANTA_ACTIVITY_RENDER'];
final _logoPath = Platform.environment['SEND_BRANTA_LOGO'];
final _shotKey = GlobalKey();

SparkTransaction _spark(String id, int sats, DateTime at,
        {TransactionType direction = TransactionType.received,
        SparkTransactionType type = SparkTransactionType.spark}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: type,
      direction: direction,
      pending: false,
    );

Future<Uint8List> _logo(WidgetTester tester) async {
  final path = _logoPath;
  if (path != null && File(path).existsSync()) {
    return File(path).readAsBytesSync();
  }
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 128),
        Paint()..color = Colors.white);
    canvas.drawRect(const Rect.fromLTWH(24, 40, 80, 48),
        Paint()..color = const Color(0xFFB8903C));
    final image = await recorder.endRecording().toImage(128, 128);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }))!;
}

void main() {
  if (_dir == null) return;
  late Directory hiveDir;

  setUpAll(() async {
    Directory(_dir!).createSync(recursive: true);
    hiveDir = await Directory.systemTemp.createTemp('branta_activity_render');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(BrantaPayeeRecordStore.boxName);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });
  setUp(OwnSparkArrivals.reset);
  tearDown(() => BrantaPayeeLogo.debugImageProvider = null);

  for (final dark in [false, true]) {
    testWidgets('home latest ${dark ? 'dark' : 'light'}', (tester) async {
      final logo = await _logo(tester);
      BrantaPayeeLogo.debugImageProvider = (_) => MemoryImage(logo);
      final now = DateTime.now();
      DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
      // As the send left it: the payee stored with the payment's id.
      await tester.runAsync(() => BrantaPayeeRecordStore.write(
          ['ln-to-branta'],
          BrantaPayeeRecord(
            name: 'Branta',
            logoUrl: 'https://branta.pro/logos/branta.png',
            verifiedAt: ago(4),
            rail: BrantaRail.lightning,
          )));
      final history = Transaction(
        bitcoinTransactions: const [],
        sparkTransactions: [
          _spark('ln-to-branta', 21000, ago(4),
              direction: TransactionType.sent,
              type: SparkTransactionType.lightning),
          _spark('rx_friend', 48000, ago(52)),
          _spark('plain_sent', 12000, ago(90),
              direction: TransactionType.sent),
          _spark('rx_old', 150000, ago(60 * 26)),
          _spark('rx_older', 9000, ago(60 * 30)),
        ],
        sparkUnclaimedDeposits: const [],
      );
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...portfolioOverrides(history: history),
          ...offlineVenueOverrides,
          hyperliquidActivityFillsProvider.overrideWith((_) => const []),
          currentBtcUsdProvider.overrideWithValue(100000),
          settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: '',
              reviewDone: true,
              activeWalletId: 'spending',
              wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Inter',
              brightness: dark ? Brightness.dark : Brightness.light,
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RepaintBoundary(
              key: _shotKey,
              child: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: context.colors.background,
                  body: const SingleChildScrollView(
                    padding: EdgeInsets.only(top: 12, bottom: 24),
                    child: ActivityRowStyle(
                        compact: true, child: AllActivityPreview()),
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
      // The logo decodes off the test clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('Sent to Branta'), findsOneWidget);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
      final name = 'home_latest_branta_${dark ? 'dark' : 'light'}';
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      // ignore: avoid_print
      print('RENDER wrote $_dir/$name.png');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
    });
  }
}
