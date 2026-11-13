// A look by eye at the Sends' amount steps (founder, 7 November 2026, the
// Send to anyone and Bitcoin Send amount steps: "they seem soo dense, to
// many numbers and such, please improve"), written only when asked:
// SEND_AMOUNT_RENDER=<dir>.
//
//   * "bitcoin": the Bitcoin Send's amount step (confirm_send.dart), opened
//     on a bitcoin address as a scanned one opens it;
//   * "link": Send to anyone's amount step for a bitcoin link
//     (share/send_to_anyone_sheet.dart), opened over a page as Send opens
//     it.
//
// Each at 0 and at a typed amount, light and dark, at 320, 375 and 430 pt,
// at the default text size and at 1.3x. The spending wallet holds 361,694
// sats, bitcoin at $100,000. Shadows are drawn as on a phone. One screen
// per run is safest:
//   for s in bitcoin link; do SEND_AMOUNT_RENDER=<dir> flutter test \
//     test/render/send_amount_render_test.dart --plain-name "render: $s"; \
//   done

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/services/api/share_links_api.dart'
    show shareLinksApiProvider;
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../helpers/kute_bar_test_support.dart';
import '../mocks/fake_share_links_api.dart';
import '../screens/share/share_artwork.dart';

final _dir = Platform.environment['SEND_AMOUNT_RENDER'];

const _onChain = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

Settings _settings() => Settings(
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
    );

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

/// Rates without Hive: bitcoin at $100,000.
class _Rates extends StateNotifier<CurrencyState> implements CurrencyNotifier {
  _Rates()
      : super(CurrencyState({
          'USD': Fixed.fromInt(100),
          'BTC': Fixed.parse('0.00001'),
        }));

  @override
  Future<void> updateRates() async {}
}

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

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
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

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _emptyClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        return null;
      case 'Clipboard.hasStrings':
        return {'value': false};
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

List<Override> _wallet() => [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            'spending': WalletBalance(
                onChainBtcBalance: 0, sparkBitcoinbalance: 361694),
          })),
      currencyProvider.overrideWith((_) => _Rates()),
    ];

/// The Bitcoin Send, opened on [_onChain]: straight to the amount.
Future<void> _bitcoin(WidgetTester tester, bool dark) async {
  final container = ProviderContainer(overrides: _wallet());
  addTearDown(container.dispose);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => const Scaffold(body: SizedBox.expand()),
    ),
    GoRoute(
      path: '/send',
      name: 'pay_send',
      pageBuilder: (context, state) => SendSheetPage<void>(
        key: state.pageKey,
        name: state.name,
        child: const ConfirmSend(),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        builder: withKuteShellBar,
        routerConfig: router,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final hold = container.listen(sendTxProvider, (_, __) {});
  addTearDown(hold.close);
  container.read(sendTxProvider.notifier).resetToDefault();
  container.read(sendTxProvider.notifier).updateAddress(_onChain);
  router.pushNamed('pay_send');
  await _frames(tester, 20);
  expect(find.byType(ConfirmSend), findsOneWidget);
}

/// Send to anyone for a bitcoin link, as Send opens it over a page.
Future<void> _link(WidgetTester tester, bool dark) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ..._wallet(),
      shareLinksApiProvider.overrideWithValue(FakeShareLinksApi()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: withKuteShellBar,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showSendToAnyoneSheet(context,
                    kind: ShareLinkKind.bitcoin, entrySource: 'render'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester);
  await tester.tap(find.text('open'));
  await _frames(tester);
}

/// Types [digits] on the app's keypad.
Future<void> _type(WidgetTester tester, String digits) async {
  for (final k in digits.split('')) {
    await tester.tap(find.text(k).last);
    await tester.pump(const Duration(milliseconds: 60));
  }
  await _frames(tester, 4);
}

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_amount_render');
    Hive.init(hiveDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    ShareLinksStore.debugMemory = <String, String>{};
    useShareTestArtwork();
  });

  final screens = <String, (Future<void> Function(WidgetTester, bool), String)>{
    'bitcoin': (_bitcoin, '25000'),
    'link': (_link, '5000'),
  };

  for (final MapEntry(key: screen, value: (open, typed)) in screens.entries) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3]) {
        for (final dark in [false, true]) {
          final mode = dark ? 'dark' : 'light';
          final name =
              'amount_${screen}_${width.round()}_${scale == 1.0 ? 'x1' : 'x13'}_$mode';
          testWidgets('render: $screen ${width.round()} $scale $mode',
              skip: _dir == null, (tester) async {
            await _fonts(tester);
            final height = switch (width) {
              320.0 => 568.0,
              375.0 => 667.0,
              _ => 932.0,
            };
            tester.view.physicalSize = Size(width, height);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(tester
                .platformDispatcher.clearAccessibilityFeaturesTestValue);
            _emptyClipboard(tester);
            await open(tester, dark);
            expect(tester.takeException(), isNull,
                reason: '$name overflowed');
            await _shoot(tester, '${name}_zero');
            await _type(tester, typed);
            expect(tester.takeException(), isNull,
                reason: '$name overflowed once typed');
            await _shoot(tester, '${name}_typed');
          });
        }
      }
    }
  }
}
