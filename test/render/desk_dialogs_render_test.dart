// Nothing put over a page stretches across a wide window (founder, 25
// November 2026, the "Forgot your PIN?" card edge to edge on a laptop,
// its red button a 1900 px bar: "this still wrong"). The app's overlay
// openers (an alert, the Forgot PIN alert on the real PIN screen, a small
// form alert, the result sheet, a sheet with a button, the unavailable
// sheet, a pushed page, a detail sheet) are opened at 1440x900 and
// 1180x820; every modal surface and every button they add must be at most
// `KuteLayout.columnMaxWidth` wide. The search panel and the two-pane
// pages are not opened here (they are wide by design).
//
// Also a look by eye, light and dark, at 1440x900, 1180x820, 820x1180
// (MEDIUM) and 430x932 (a phone, as before),
// written only when asked:
//   DESK_DIALOGS_RENDER=<dir> flutter test test/render/desk_dialogs_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/login/open_pin.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/screens/recovery/storage_unavailable_screen.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';

import '../helpers/kute_bar_test_support.dart';
import '../services/support/fake_secret_store.dart';

final _dir = Platform.environment['DESK_DIALOGS_RENDER'];

class _NoBiometrics extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];
}

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

final _host = GlobalKey();

/// A plain page to open things from, the shape of a tab's page.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _host,
        body: const Center(child: Text('Page')),
      );
}

/// A phone page with a full-width button, as the app's pushed pages are.
Widget _phonePage(BuildContext context) => Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Details', style: AppTextStyles.heading2(context)),
              const Spacer(),
              AppButton(text: context.l10n.done, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

typedef _Opener = Future<void> Function(WidgetTester tester);

BuildContext _ctx() => _host.currentContext!;

void _go(Future<Object?> Function(BuildContext) open) {
  // Not awaited: the opener's future ends when the overlay closes.
  // ignore: discarded_futures
  open(_ctx());
}

/// The overlay openers (name, needs the PIN screen, opener).
final Map<String, (bool, _Opener)> _openers = {
  'forgot_pin': (
    true,
    (tester) async {
      await tester.tap(find.text('Forgot PIN?'));
    }
  ),
  'alert_raw_actions': (
    false,
    (tester) async {
      _go((c) => showKuteAlert<bool>(
            context: c,
            builder: (ctx) => CustomAlertDialog(
              title: ctx.l10n.openBitcoinApp,
              content: ctx.l10n.ledgerBitcoinAppNotOpenMessage,
              actions: [
                AppButton(
                    text: ctx.l10n.retry,
                    compact: true,
                    onPressed: () => Navigator.of(ctx).pop(true)),
                AppButton(
                    text: ctx.l10n.cancel,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                    onPressed: () => Navigator.of(ctx).pop(false)),
              ],
            ),
          ));
    }
  ),
  'alert_form': (
    false,
    (tester) async {
      _go((c) => showKuteAlert<void>(
            context: c,
            barrierDismissible: true,
            builder: (ctx) => KuteAlertShell(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ctx.l10n.rename,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading2(ctx)),
                  const SizedBox(height: 16),
                  const TextField(),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: CustomButton(
                            onPressed: () {},
                            text: ctx.l10n.cancel,
                            primaryColor: ctx.colors.surfaceLight,
                            textColor: ctx.colors.textPrimary)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: CustomButton(
                            onPressed: () {},
                            text: ctx.l10n.save,
                            primaryColor: ctx.ctaFill)),
                  ]),
                ],
              ),
            ),
          ));
    }
  ),
  'confirmation': (
    false,
    (tester) async {
      final navigator = Navigator.of(_ctx(), rootNavigator: true);
      pushKuteSuccessOverlay(
        navigator: navigator,
        overlay: KuteConfirmation(
          message: 'Moved to Dollars',
          amount: r'$25.00',
          rows: const {'From': 'Bitcoin'},
          secondaryButtonText: 'View activity',
          onSecondary: () {},
          onDone: () => navigator.pop(),
        ),
      );
    }
  ),
  'sheet_with_button': (
    false,
    (tester) async {
      _go((c) => showAppBottomSheet<void>(
            context: c,
            builder: (ctx) => AppBottomSheetContainer(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDecorations.dragHandle(ctx),
                    const SizedBox(height: 16),
                    Text(ctx.l10n.rename,
                        style: AppTextStyles.heading2(ctx)),
                    const SizedBox(height: 24),
                    AppButton(text: ctx.l10n.save, onPressed: () {}),
                    AppTextButton(text: ctx.l10n.cancel, onPressed: () {}),
                  ],
                ),
              ),
            ),
          ));
    }
  ),
  'unavailable_sheet': (
    false,
    (tester) async {
      _go((c) => showBuyUnavailableSheet(c));
    }
  ),
  'toast': (
    false,
    (tester) async {
      showMessageSnackBar(
          context: _ctx(),
          message: 'Couldn\'t reach the network. Check your connection.',
          error: true);
    }
  ),
  'pushed_page': (
    false,
    (tester) async {
      _go((c) => Navigator.of(c, rootNavigator: true)
          .push<void>(KutePageRoute(builder: _phonePage)));
    }
  ),
  'detail_sheet': (
    false,
    (tester) async {
      _go((c) => Navigator.of(c, rootNavigator: true)
          .push<void>(KuteSheetPageRoute(builder: _phonePage)));
    }
  ),
};

Set<RenderObject> _renderObjects(WidgetTester tester) {
  final all = <RenderObject>{};
  void visit(RenderObject o) {
    all.add(o);
    o.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return all;
}

bool _painted(Decoration d) {
  if (d is BoxDecoration) {
    final fill = d.color;
    return (fill != null && fill.a > 0) ||
        d.border != null ||
        d.gradient != null ||
        (d.boxShadow?.isNotEmpty ?? false);
  }
  return d is ShapeDecoration;
}

/// Every button on screen and every painted surface the overlay added
/// (not on screen before it opened) is at most a column wide.
void _expectNothingStretched(
    WidgetTester tester, String label, Set<RenderObject> before) {
  const limit = KuteLayout.columnMaxWidth + 0.5;
  for (final finder in [
    find.byType(AppButton),
    find.byType(AppTextButton),
    find.byType(KuteBarPrimaryButton),
  ]) {
    for (final e in finder.evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      // The button's own surface: its widest painted descendant.
      var widest = 0.0;
      void visit(RenderObject o) {
        if (o is RenderDecoratedBox && o.hasSize && _painted(o.decoration)) {
          widest = o.size.width > widest ? o.size.width : widest;
        }
        o.visitChildren(visit);
      }

      visit(box);
      expect(widest, lessThanOrEqualTo(limit),
          reason: '$label: a ${e.widget.runtimeType} is $widest wide');
    }
  }
  for (final o in _renderObjects(tester).difference(before)) {
    if (o is! RenderBox || !o.hasSize || !o.attached) continue;
    final painted = switch (o) {
      RenderDecoratedBox(:final decoration) => _painted(decoration),
      // A Material's surface (a dialog's, a page's Scaffold).
      RenderPhysicalShape(:final color) => color.a > 0,
      RenderPhysicalModel(:final color) => color.a > 0,
      _ => false,
    };
    if (!painted || o.size.height < 24) continue;
    expect(o.size.width, lessThanOrEqualTo(limit),
        reason: '$label: a surface ${o.size} (${o.runtimeType}) '
            'stretches across the window; created by ${o.debugCreator}');
  }
}

void main() {
  late FakeKeychain keychain;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    StorageUnavailableScreen.debugReset();
  });

  tearDown(SecretStores.debugReset);

  Future<void> pumpApp(WidgetTester tester,
      {required Size size, required bool dark, required bool pin}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
    ]);
    addTearDown(container.dispose);
    container.read(storageBootStateProvider.notifier).state =
        StorageBootState.ok;
    final router = GoRouter(initialLocation: pin ? '/open_pin' : '/', routes: [
      // The app's form page (app_router.dart): a centred column.
      GoRoute(
          path: '/open_pin',
          builder: (_, __) =>
              KuteFormColumn(child: OpenPin(localAuth: _NoBiometrics()))),
      GoRoute(path: '/', builder: (_, __) => const _Host()),
    ]);
    addTearDown(router.dispose);
    final base = dark ? buildDarkTheme() : buildLightTheme();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: KuteLayout.designSizeFor(size),
        builder: (_, __) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          builder: withKuteShellBar,
          routerConfig: router,
          theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'Inter')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final entry in _openers.entries) {
    final (pin, open) = entry.value;
    for (final (label, size) in [
      ('1440x900', const Size(1440, 900)),
      ('1180x820', const Size(1180, 820)),
      ('820x1180', const Size(820, 1180)),
    ]) {
      testWidgets('${entry.key} at $label: nothing wider than a column',
          (tester) async {
        await pumpApp(tester, size: size, dark: false, pin: pin);
        final before = _renderObjects(tester);
        await open(tester);
        await settle(tester);
        expect(tester.takeException(), isNull);
        _expectNothingStretched(tester, '${entry.key} at $label', before);
        // Unmount while the overlay is up: nothing left running.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    for (final (label, size) in [
      ('1440x900', const Size(1440, 900)),
      ('1180x820', const Size(1180, 820)),
      ('820x1180', const Size(820, 1180)),
      ('430x932', const Size(430, 932)),
    ]) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: ${entry.key} $label $mode', skip: _dir == null,
            (tester) async {
          await _fonts(tester);
          await pumpApp(tester, size: size, dark: dark, pin: pin);
          await open(tester);
          await settle(tester);
          expect(tester.takeException(), isNull);
          await _shoot(tester, '${entry.key}_${label}_$mode');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
