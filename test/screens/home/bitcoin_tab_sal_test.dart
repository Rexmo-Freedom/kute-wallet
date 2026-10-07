// The wallet home's first tab, "Bitcoin": while it is the selected tab its
// mark is Sal holding a bitcoin (KuteDogBitcoin), who tosses and catches it
// on becoming selected and then every 10 s, resting in between; selected
// elsewhere, the plain dog. Still under Reduce Motion.

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

  testWidgets('the selected Bitcoin tab is Sal with his coin, the tab the '
      'same size', (tester) async {
    await _pumpStrip(tester, ActiveNavTab.home);
    final sal = find.byKey(const ValueKey('bitcoin-tab-sal'));
    expect(sal, findsOneWidget);
    expect(tester.widget<KuteDogBitcoin>(sal).size, 24.sp);
    expect(tester.getSize(sal), Size.square(24.sp));
    expect(_plainDog(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('another tab selected: the plain dog, no coin', (tester) async {
    await _pumpStrip(tester, ActiveNavTab.trading);
    expect(find.byType(KuteDogBitcoin), findsNothing);
    expect(_plainDog(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
