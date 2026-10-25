// The Bitcoin send's amount always opens in Bitcoin units (founder
// decision): sats, or BTC when that is the Bitcoin unit in Settings —
// never dollars, whatever the display currency, the unit last picked on
// Receive, or the unit a previous send was flipped to. Fiat stays one
// flip away within the flow; the next send opens in Bitcoin again.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/address_receive_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/pay/components/confirm_send.dart';
import 'package:kute/screens/shared/send/send_sheet.dart';
import 'package:kute/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

Settings _settings({required String btcFormat, String currency = 'USD'}) =>
    Settings(
      currency: currency,
      language: 'en',
      btcFormat: btcFormat,
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      activeWalletId: 'spending',
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );

const _onChain = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const _lightningAddress = 'satoshi@kute.app';
const _lnurl =
    'lnurl1dp68gurn8ghj7ctsdyh85etzv4jx2efwd9hj7a3s9acxz7tvdaskgtthd96xserjv9mkzmpdwfjhgatp';

/// BOLT 11's "donation of any amount" example: an invoice with no amount.
const _amountlessInvoice =
    'lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql';

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

Future<(ProviderContainer, GoRouter)> _pump(WidgetTester tester,
    {required String btcFormat}) async {
  tester.view.physicalSize = const Size(1125, 2436);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  _emptyClipboard(tester);
  final container = ProviderContainer(overrides: [
    settingsProvider
        .overrideWith((_) => SettingsModel(_settings(btcFormat: btcFormat))),
  ]);
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
        routerConfig: router,
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

/// A few frames, not a settle: a recipient that resolves over the network
/// (Lightning address, LNURL) keeps a spinner going in tests.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the send with [recipient] preset, as the scanner, a payment link
/// or a contact does; null opens it empty, as the dock does.
Future<void> _open(WidgetTester tester, ProviderContainer container,
    GoRouter router, String? recipient) async {
  final hold = container.listen(sendTxProvider, (_, __) {});
  addTearDown(hold.close);
  container.read(sendTxProvider.notifier).resetToDefault();
  if (recipient != null) {
    container.read(sendTxProvider.notifier).updateAddress(recipient);
  }
  router.pushNamed('pay_send');
  await _frames(tester);
  expect(find.byType(ConfirmSend), findsOneWidget);
}

Future<void> _close(WidgetTester tester, GoRouter router) async {
  router.pop();
  await _frames(tester);
  await tester.pumpAndSettle(const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
  expect(find.byType(ConfirmSend), findsNothing);
}

/// The step on screen, by the header its page announces.
Finder _step(String title) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.header == true &&
    w.properties.label == title);

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('send_amount_unit');
    Hive.init(hiveDir.path);
    // The unit last picked on Receive was dollars: Send must not inherit it.
    final box = await Hive.openBox('settings');
    await box.put(kReceiveUnitPrefKey, 'USD');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('bitcoinEntryUnit', () {
    test('BTC only when the setting is BTC, sats otherwise', () {
      expect(bitcoinEntryUnit('BTC'), 'BTC');
      expect(bitcoinEntryUnit('sats'), 'Sats');
      expect(bitcoinEntryUnit('mBTC'), 'Sats');
      expect(bitcoinEntryUnit('bits'), 'Sats');
    });
  });

  group('the send unit provider', () {
    for (final (format, unit) in [('sats', 'Sats'), ('BTC', 'BTC')]) {
      test(
          'defaults to $unit (setting $format), not the Receive unit '
          'or the display currency', () {
        final container = ProviderContainer(overrides: [
          settingsProvider.overrideWith((_) =>
              SettingsModel(_settings(btcFormat: format, currency: 'EUR'))),
        ]);
        addTearDown(container.dispose);
        expect(container.read(inputCurrencyProvider), unit);
        // Receive keeps its remembered pick.
        expect(container.read(receiveInputCurrencyProvider), 'USD');
      });
    }

    test('a fiat pick is forgotten once the send closes', () async {
      final container = ProviderContainer(overrides: [
        settingsProvider
            .overrideWith((_) => SettingsModel(_settings(btcFormat: 'sats'))),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(inputCurrencyProvider, (_, __) {});
      container.read(inputCurrencyProvider.notifier).state = 'USD';
      expect(container.read(inputCurrencyProvider), 'USD');
      sub.close();
      await container.pump();
      expect(container.read(inputCurrencyProvider), 'Sats');
    });
  });

  for (final (format, unit) in [('sats', 'Sats'), ('BTC', 'BTC')]) {
    group('setting $format, display currency USD', () {
      final paths = <(String, String?)>[
        ('the dock (no recipient yet)', null),
        ('an on-chain address', _onChain),
        ('a Lightning address', _lightningAddress),
        ('an LNURL', _lnurl),
        ('a scanned invoice with no amount', _amountlessInvoice),
      ];
      for (final (name, recipient) in paths) {
        testWidgets('$name opens the amount in $unit', (tester) async {
          final (container, router) = await _pump(tester, btcFormat: format);
          await _open(tester, container, router, recipient);
          expect(container.read(inputCurrencyProvider), unit);
          // Past the first frame too (the old fiat default landed there).
          await _frames(tester);
          expect(container.read(inputCurrencyProvider), unit);
        });
      }

      testWidgets('flipping to dollars lasts for this send only',
          (tester) async {
        final (container, router) = await _pump(tester, btcFormat: format);
        await _open(tester, container, router, _onChain);
        expect(_step(_l10n.amount), findsOneWidget);
        expect(container.read(inputCurrencyProvider), unit);

        await tester.tap(find.byIcon(Icons.swap_vert_rounded));
        await _frames(tester);
        expect(container.read(inputCurrencyProvider), 'USD');

        await _close(tester, router);
        await _open(tester, container, router, _onChain);
        expect(_step(_l10n.amount), findsOneWidget);
        expect(container.read(inputCurrencyProvider), unit);
        await _frames(tester);
        expect(container.read(inputCurrencyProvider), unit);
      });
    });
  }
}
