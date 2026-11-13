// A look by eye at the app's one card surface on sheets (founder, 7
// November 2026: "dofferent cards than this"; kute_action_cards.dart), light
// and dark, written only when asked: CARD_SURFACE_RENDER=<dir>.
//
//   * "receive": the Bitcoin Receive's "Receive or swap" sheet, its three
//     big cards (the sheet is white in light mode, the theme's sheet
//     surface in dark);
//   * "picker": the Add money picker's two cards on the theme's sheet
//     surface (deposit_sheet.dart's picker chrome, the surface every
//     AppBottomSheetContainer wears), with a disabled card's badge;
//   * "receipt": a receipt's fact tiles on the same sheet surface.
//
// Shadows are drawn as on a phone (flutter_test paints them flat by
// default), so the soft card reads as it does in the app. One render per
// run is safest:
//   for v in 'receive light' 'receive dark' 'picker light' 'picker dark' \
//       'receipt light' 'receipt dark'; do CARD_SURFACE_RENDER=<dir> \
//     flutter test test/render/card_surface_render_test.dart \
//     --plain-name "$v"; done

import 'dart:async';
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
import 'package:kute/models/account.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MovePickerRow;
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/receipt_parts.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/services/orchestra/receive_minimums.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';

final _dir = Platform.environment['CARD_SURFACE_RENDER'];

class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

final _catalog = OrchestraRoutesCatalog.fromJson(
  {
    'assets': [
      _row('spark', 'BTC', decimals: 8),
      _row('spark', 'USDB'),
      _row('base', 'USDC'),
      _row('ethereum', 'USDT'),
      _row('ethereum', 'ETH', decimals: 18),
      _row('solana', 'SOL', decimals: 9),
    ],
  },
  source: OrchestraCatalogSource.live,
  fetchedAt: DateTime.now(),
);

final _spending = WalletConfig(id: 'spending', name: 'Spending');

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

/// The whole screen, the page and the sheet over it, as a PNG; the
/// shadows drawn as on a phone for the frame shot, then flat again (the
/// test binding checks the flag is back).
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

/// A plain page with a button that opens [open].
Widget _app(bool dark, void Function(BuildContext) open,
        {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
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
                  onPressed: () => open(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    await policy.refresh();
  });
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('render: receive $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(dark, showBitcoinReceiveSheet, overrides: [
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
              wallets: [_spending],
            ))),
        selectedAccountProvider
            .overrideWithValue(BtcSpendingAccount(_spending)),
        swapOffersEnabledProvider.overrideWithValue(true),
        orchestraSupportedRoutesProvider
            .overrideWith((_) => _Routes(_catalog)),
        orchestraRoutesReadyProvider.overrideWith((_) async {}),
        standingDestinationsProvider
            .overrideWith((_) async => {'spark:USDB'}),
        receiveMinimumsProvider
            .overrideWithValue(ReceiveMinimums(fetch: (_) async => null)),
        usdBalanceProvider.overrideWithValue(4.75),
        usdBalanceUnknownProvider.overrideWithValue(false),
        breezSDKProvider
            .overrideWith((_) => Completer<BreezSdkSpark>().future),
      ]));
      await _open(tester);
      expect(find.byKey(const ValueKey('bitcoin-receive-bitcoin')),
          findsOneWidget);
      await _shoot(tester, 'sheet_receive_$mode');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('render: picker $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        dark,
        (context) => showAppBottomSheet<void>(
          context: context,
          builder: (sheet) {
            final l10n = sheet.l10n;
            return AppBottomSheetContainer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppBottomSheetHeader(title: 'Add money to Dollars'),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: KuteActionCardGrid(cards: [
                      MovePickerRow(
                        asset: 'lib/assets/bitcoin-icon.svg',
                        title: 'Bitcoin',
                        subtitle: l10n
                            .depositFromSpendingWalletWithBalance(r'$285.48'),
                        onTap: () {},
                      ).toCard(),
                      MovePickerRow(
                        icon: Icons.south_west_rounded,
                        title: l10n.receiveAnotherCrypto,
                        subtitle: l10n.depositFromAnotherWalletSubtitle,
                        onTap: () {},
                      ).toCard(),
                      MovePickerRow(
                        icon: Icons.account_balance_rounded,
                        title: 'Bank transfer',
                        subtitle: 'From your bank account',
                        disabled: true,
                        onTap: () {},
                      ).toCard(),
                    ]),
                  ),
                  SizedBox(height: 24.h),
                ],
              ),
            );
          },
        ),
      ));
      await _open(tester);
      await _shoot(tester, 'sheet_picker_$mode');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('render: receipt $mode', skip: _dir == null, (tester) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        dark,
        (context) => showAppBottomSheet<void>(
          context: context,
          builder: (sheet) => AppBottomSheetContainer(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 24.h),
              child: const ReceiptFactTiles(facts: [
                ReceiptFact(label: 'Amount', value: r'$24.10'),
                ReceiptFact(label: 'Fee', value: r'$0.12', sub: '0.5%'),
                ReceiptFact(label: 'Network', value: 'Lightning'),
                ReceiptFact(label: 'Status', value: 'Completed'),
              ]),
            ),
          ),
        ),
      ));
      await _open(tester);
      await _shoot(tester, 'sheet_receipt_$mode');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
