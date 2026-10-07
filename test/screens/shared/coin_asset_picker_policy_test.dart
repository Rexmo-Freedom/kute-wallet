import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/runtime_policy_fixture.dart';

OrchestraReceiveOption _row(String chain, String asset, String name) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: name,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
    );

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  OrchestraReceiveOption? picked;
  Future<void> pump(WidgetTester tester) async {
    picked = null;
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: CoinAssetPickerSheet(
              groups: groupCoinsByAsset([
                _row('base', 'USDC', 'USD Coin'),
                _row('ethereum', 'ETH', 'Ether'),
                _row('hypercore', 'USDC', 'Investing'),
              ]),
              title: 'Where to',
              subtitle: 'Pick a coin',
              emptyLabel: 'Nothing',
              flow: 'send',
              onPicked: (o) => picked = o,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('altcoins blocked: stablecoins stay, the reason is said once',
      (tester) async {
    final policy = runtimePolicyFixture(blocked: {'orchestra.swap.altcoins'});
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    await pump(tester);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('ETH'), findsNothing);
    expect(find.text('This feature is currently unavailable in Kute.'),
        findsOneWidget);
    policy.dispose();
  });

  testWidgets('master blocked: only the venue leg remains', (tester) async {
    final policy = runtimePolicyFixture(blocked: {
      'orchestra.swap',
      'orchestra.swap.stablecoins',
      'orchestra.swap.altcoins'
    });
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    await pump(tester);
    // USDC survives through its Investing network alone.
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('ETH'), findsNothing);
    // One network left is picked straight away, and it is the venue one.
    await tester.tap(find.text('USDC'));
    await tester.pumpAndSettle();
    expect(picked?.chain, 'hypercore');
    policy.dispose();
  });

  testWidgets('nothing blocked: every coin is offered, no notice',
      (tester) async {
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    await pump(tester);
    expect(find.text('USDC'), findsOneWidget);
    expect(find.text('ETH'), findsOneWidget);
    expect(find.textContaining('unavailable'), findsNothing);
    policy.dispose();
  });
}
