// A look by eye at the Financial hub (fw49; founder, 7 November 2026:
// "with the bigger cards just like the other parts of the app now"), light
// and dark, written only when asked: FINANCIAL_HUB_RENDER=<dir>. Settings
// on top, Referrals and Support under it, then the accounts (the spending
// account, a Bitcoin account and a Ledger) and Add account on the same
// soft card; "withheld": the referral program withheld, Rate the app in
// its card. Shadows are drawn as on a phone. One render per run:
//   for v in 'hub light' 'hub dark' 'withheld light' 'withheld dark'; do
//     FINANCIAL_HUB_RENDER=<dir> flutter test \
//     test/render/financial_hub_render_test.dart --plain-name "$v"; done

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/wallet_money_actions.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';

final _dir = Platform.environment['FINANCIAL_HUB_RENDER'];

final _wallets = [
  WalletConfig(id: 'spending', name: 'Spending Wallet'),
  WalletConfig(
      id: 'savings',
      name: 'Savings',
      sparkEnabled: false,
      walletType: 'bitcoin'),
  WalletConfig(
      id: 'ledger',
      name: 'Ledger',
      sparkEnabled: false,
      isHardware: true,
      walletType: 'ledger'),
];

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      // The spending account's Sal, as on a phone.
      final manifest = jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>;
      SalSpriteCache.debugSetManifest(manifest);
      await SalSpriteCache.clip('idle', 2);
      await SalSpriteCache.clip('idle', 3);
    });

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

/// The whole screen, the page and the hub over it, as a PNG, the shadows
/// drawn as on a phone for the shot, then flat again.
Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  tester.binding.renderViews.first.markNeedsPaint();
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final (variant, referral) in [('hub', true), ('withheld', false)]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('render: $variant $mode', skip: _dir == null, (tester) async {
        final policy = runtimePolicyFixture(
            also: {'affiliate.program'},
            blocked: {if (!referral) 'affiliate.program'});
        RuntimeCapabilitiesService.debugInstance = policy;
        await tester.runAsync(policy.refresh);
        await _fonts(tester);
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
                  wallets: _wallets,
                ))),
          ],
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () =>
                          showWalletMoneyActions(context, source: 'home_plus'),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('hub-cards')), findsOneWidget);
        await _shoot(tester,
            referral ? 'financial_hub_$mode' : 'financial_hub_withheld_$mode');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
