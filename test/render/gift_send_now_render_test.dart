// A look by eye at "Send now" funding a short Dollars
// (claimed_prompt_sheet.dart, one_balance/gift_funding.dart): the sheet with
// the leg and its fee before the tap, the money's steps while it runs, and
// the stop, with Kute asking again. Light and dark, on a 390 pt phone. Every
// frame lays out without an overflow; the PNGs are written only when asked:
//
//   GIFT_SEND_NOW_RENDER=<dir> flutter test \
//     test/render/gift_send_now_render_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/share/claimed_prompt_sheet.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show spendingBitcoinLandingUsdProvider;
import 'package:kute/services/one_balance/gift_funding.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService;
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../screens/share/cards/share_card_test_fonts.dart';
import '../screens/share/gift_funding_sheet_harness.dart';
import '../screens/share/share_artwork.dart';

final String? _dir = Platform.environment['GIFT_SEND_NOW_RENDER'];

void main() {
  late GiftSheetWallet wallet;

  setUpAll(() => Hive.init(
      Directory.systemTemp.createTempSync('gift_send_now_hive').path));

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    ShareLinksStore.debugMemory = <String, String>{};
    ShareLinksStore.put(PendingShareLink(
      id: 'lnk_gift',
      kind: ShareLinkKind.dollars,
      amountMinor: 2000,
      label: 'Ana',
      url: '',
      createdAt: DateTime(2026, 11, 8),
      status: ShareLinkStatus.claimed,
    ));
    useShareTestArtwork();
    GiftFundingRunner.debugReset();
    wallet = GiftSheetWallet();
    ClaimedPromptSheet.debugPayer = wallet.pay;
    final open = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = open;
    await open.refresh();
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    ClaimedPromptSheet.debugPayer = null;
    ShareLinksStore.debugMemory = null;
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final error = tester.takeException();
    expect(error, isNull, reason: '$name: $error');
    final dir = _dir;
    if (dir == null) return;
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> frames(WidgetTester tester, [int n = 14]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(loadShareCardFonts);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider
            .overrideWith((ref) => SettingsModel(giftSheetSettings)),
        usdBalanceProvider.overrideWith((_) => wallet.dollars),
        spendingBitcoinLandingUsdProvider.overrideWith((ref) => 40.0),
        aiEnabledProvider.overrideWith((ref) async => false),
        ...wallet.overrides(),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: withKuteShellBar,
          home: Scaffold(
            backgroundColor: dark ? const Color(0xFF111111) : Colors.white,
            body: Align(
              alignment: Alignment.bottomCenter,
              child:
                  ClaimedPromptSheet(claim: giftSheetClaim(amountMinor: 2000)),
            ),
          ),
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
        ),
      ),
    ));
    await frames(tester);
  }

  for (final dark in [false, true]) {
    final tone = dark ? 'dark' : 'light';

    testWidgets('$tone: Dollars enough, the sheet as it was', (tester) async {
      wallet.dollars = 50;
      await pump(tester, dark: dark);
      expect(find.byKey(const ValueKey('share-claimed-funding')), findsNothing);
      await capture(tester, 'send_now_dollars_enough_$tone');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$tone: Send now with a shortfall', (tester) async {
      await pump(tester, dark: dark);
      expect(
          find.byKey(const ValueKey('share-claimed-funding')), findsOneWidget);
      await capture(tester, 'send_now_shortfall_$tone');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$tone: in progress', (tester) async {
      wallet.landing = Completer<void>();
      await pump(tester, dark: dark);
      await tester.tap(kuteBarPrimary);
      await frames(tester, 24);
      expect(find.byKey(const ValueKey('share-claimed-steps')), findsOneWidget);
      await capture(tester, 'send_now_in_progress_$tone');
      wallet.landing!.complete();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await frames(tester, 8);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$tone: failed', (tester) async {
      wallet.failLeg = true;
      await pump(tester, dark: dark);
      await tester.tap(kuteBarPrimary);
      await frames(tester, 4);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await frames(tester, 24);
      expect(find.byKey(const ValueKey('share-claimed-steps')), findsOneWidget);
      await capture(tester, 'send_now_failed_$tone');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
