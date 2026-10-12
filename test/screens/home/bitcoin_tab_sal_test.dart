// The top tab strip draws Bitcoin, Dollars, Investing and Predictions with
// one icon family at one size (user decision 2026-10-12: no mascot, no
// dollar mark, no venue logos). The KuteDogBitcoin glyph tests below pin
// the scene widget itself, still used elsewhere.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => true;
}

Future<void> _pumpStrip(WidgetTester tester, ActiveNavTab tab) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final policy = _Policy();
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWithValue(policy),
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
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      shellWalletIdProvider.overrideWith((_) => null),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FloatingActionPill(activeTab: tab)),
      ),
    ),
  ));
  await tester.pump();
}

Finder _plainDog() => find.byWidgetPredicate((w) =>
    w is SvgPicture &&
    w.bytesLoader is SvgAssetLoader &&
    (w.bytesLoader as SvgAssetLoader).assetName.contains('kute_dog'));

Widget _glyph() => const MaterialApp(
    home: Scaffold(body: Center(child: KuteDogBitcoin(size: 24))));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the four tabs share one icon family: Bitcoin, dollars, a '
      'rising trend and a ring, no mascot or logos', (tester) async {
    for (final tab in [ActiveNavTab.home, ActiveNavTab.trading]) {
      await _pumpStrip(tester, tab);
      expect(find.byIcon(Icons.currency_bitcoin_rounded), findsOneWidget);
      expect(find.byIcon(Icons.attach_money_rounded), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.donut_large_rounded), findsOneWidget);
      expect(find.byType(KuteDogBitcoin), findsNothing);
      expect(_plainDog(), findsNothing);
      expect(find.byType(SvgPicture), findsNothing);
      for (final icon in [
        Icons.currency_bitcoin_rounded,
        Icons.attach_money_rounded,
        Icons.trending_up_rounded,
        Icons.donut_large_rounded,
      ]) {
        expect(tester.widget<Icon>(find.byIcon(icon)).size, 24.sp);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('he tosses the coin on appearing, rests, and tosses it again '
      'after 10 s', (tester) async {
    await tester.pumpWidget(_glyph());
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 9800));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('under Reduce Motion he just holds the coin', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_glyph());
    expect(
        find.descendant(
            of: find.byType(KuteDogBitcoin),
            matching: find.byType(AnimatedBuilder)),
        findsNothing);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('paints in light and dark at 1x, 2x and 3x', (tester) async {
    for (final dark in [false, true]) {
      for (final dpr in [1.0, 2.0, 3.0]) {
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(extensions: [
              dark ? AppColorsExtension.dark() : AppColorsExtension.light()
            ]),
            home: const Scaffold(
                body: Center(child: KuteDogBitcoin(size: 24)))));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(KuteDogBitcoin)),
            const Size.square(24));
      }
    }
  });
}
