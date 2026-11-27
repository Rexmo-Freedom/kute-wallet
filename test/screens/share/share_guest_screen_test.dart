// A shared market with no wallet (share_guest_screen.dart): both venues'
// pages draw from public data with no wallet at all and contact only the
// venues' public hosts; a slip opened with no wallet meets the wallet gate
// (share_wallet_gate.dart), and a region that refuses the venue's trading
// says so with the policy's own sheet before anything is made.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/hive_registrar.g.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/share/share_guest_screen.dart';
import 'package:kute/screens/share/share_wallet_gate.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/runtime_policy_fixture.dart';

PolymarketEvent _event() => PolymarketEvent(
      id: '9',
      slug: 'will-it-rain',
      title: 'Will it rain?',
      volume: 1000,
      liquidity: 100,
      category: 'weather',
      conditionId: '0x9',
      endDate: DateTime.now().add(const Duration(days: 30)),
      outcomes: [
        PolymarketOutcome(
            gammaMarketId: 'm1', name: 'Yes', price: 0.6, tokenId: 'a'),
        PolymarketOutcome(
            gammaMarketId: 'm2', name: 'No', price: 0.4, tokenId: 'b'),
      ],
    );

HlMarket _btc() => HlMarket(
    coin: 'BTC',
    wireCoin: 'BTC',
    assetId: 0,
    kind: HlMarketKind.perp,
    szDecimals: 2,
    maxLeverage: 10,
    onlyIsolated: false,
    markPx: 100,
    midPx: 100,
    prevDayPx: 99,
    dayNtlVlm: 1e6,
    category: 'crypto',
    dex: '',
    isHip3: false);

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('share_guest');
    Hive.init(dir.path);
    Hive.registerAdapters();
    await openStartupHiveBoxes(region: () async => 'US');
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    ShareGuestScreen.debugPolyEvent = (_) async => _event();
    ShareGuestScreen.debugHlMarket = (_) async => _btc();
  });
  tearDown(() {
    ShareGuestScreen.debugPolyEvent = null;
    ShareGuestScreen.debugHlMarket = null;
    ShareWalletGate.debugWeb = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
  });

  Widget app(Widget home) => ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      );

  Future<Set<String>> pumpGuest(WidgetTester tester, ShareTarget t) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hosts = <String>{};
    await http.runWithClient(() async {
      await tester.pumpWidget(app(ShareGuestScreen(target: t)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }, () => MockClient((r) async {
          hosts.add(r.url.host);
          return http.Response('{}', 404);
        }));
    return hosts;
  }

  testWidgets('Predictions: the market with no wallet, public hosts only',
      (tester) async {
    final hosts = await pumpGuest(
        tester, ShareTarget.of(investing: false, slug: 'will-it-rain')!);
    expect(find.text('Will it rain?'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(hosts.every((h) => h.endsWith('polymarket.com')), isTrue,
        reason: '$hosts');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('Investing: the market with no wallet, public hosts only',
      (tester) async {
    final hosts =
        await pumpGuest(tester, ShareTarget.of(investing: true, slug: 'BTC')!);
    expect(find.text('BTC'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(hosts.every((h) => h == 'api.hyperliquid.xyz'), isTrue,
        reason: '$hosts');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a blocked region: the VPN sheet, no wallet step, nothing parked',
      (tester) async {
    final policy = runtimePolicyFixture(
        blocked: {'polymarket.trade'},
        reasons: {'polymarket.trade': 'country_blocked'});
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
    ShareWalletGate.debugWeb = true;
    ShareLinksStore.takeParkedShareTarget();
    var resumed = false;
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
            onPressed: () => ShareWalletGate.open(context,
                target: ShareTarget.of(investing: false, slug: 'a-b'),
                resume: () => resumed = true),
            child: const Text('Yes')))));
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('check your VPN settings'), findsOneWidget);
    expect(ShareLinksStore.parkedShareTarget, isNull);
    expect(resumed, isFalse);
  });

  testWidgets('the gate applies only with no wallet on the web',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(ShareWalletGate.needsWallet(ctx), isFalse); // not the web
    ShareWalletGate.debugWeb = true;
    expect(ShareWalletGate.needsWallet(ctx), isTrue); // web, no wallet
  });
}
