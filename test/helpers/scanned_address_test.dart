import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/scanner/scanner_sheet.dart';
import 'package:kute/screens/shared/kute_paste_chip.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/theme/app_theme.dart';

import 'fake_scanner_camera.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _sparkLong =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _evm = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';
const _usdcContract = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _btc = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';

void main() {
  group('bareRecipientAddress', () {
    test('bare addresses come back trimmed and untouched', () {
      expect(bareRecipientAddress('  $_spark \n'), _spark);
      expect(bareRecipientAddress(_evm), _evm);
      expect(bareRecipientAddress(_tron), _tron);
    });

    test('bitcoin: is stripped the way the bitcoin send strips it', () {
      expect(bareRecipientAddress('bitcoin:$_btc?amount=0.001'), _btc);
      expect(bareRecipientAddress('BITCOIN:$_btc'), _btc);
    });

    test('spark:, tron: and solana: lose scheme and query', () {
      expect(bareRecipientAddress('spark:$_spark?amount=5'), _spark);
      expect(bareRecipientAddress('tron:$_tron?amount=1'), _tron);
      expect(
          bareRecipientAddress(
              'solana:7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU?amount=1'),
          '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU');
    });

    test('EIP-681: chain id and pay- prefix go', () {
      expect(bareRecipientAddress('ethereum:$_evm@8453'), _evm);
      expect(bareRecipientAddress('ethereum:pay-$_evm@1?value=1e18'), _evm);
    });

    test('EIP-681 token transfer pays the address param, never the token', () {
      expect(
          bareRecipientAddress(
              'ethereum:$_usdcContract@8453/transfer?address=$_evm&uint256=1e6'),
          _evm);
      // No recipient named, or another function: left whole so the
      // field's chain check refuses it.
      const noTo = 'ethereum:$_usdcContract@8453/transfer?uint256=1e6';
      expect(bareRecipientAddress(noTo), noTo);
      const approve = 'ethereum:$_usdcContract/approve?address=$_evm';
      expect(bareRecipientAddress(approve), approve);
    });

    test('invoices and unknown schemes stay whole', () {
      const ln = 'lightning:lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwz';
      expect(bareRecipientAddress(ln), ln);
      expect(bareRecipientAddress('https://example.com/x'),
          'https://example.com/x');
    });

    test(
        'the dollar send check accepts a scanned URI for its own chain and '
        'refuses another network', () {
      expect(
          usdSendChainAcceptsAddress(
              'base', bareRecipientAddress('ethereum:$_evm@8453')),
          isTrue);
      expect(
          usdSendChainAcceptsAddress(
              'spark', bareRecipientAddress('spark:$_spark')),
          isTrue);
      expect(
          usdSendChainAcceptsAddress(
              'spark', bareRecipientAddress('spark:$_sparkLong?amount=1')),
          isTrue);
      // A bitcoin code scanned into a Base recipient: wrong network.
      expect(
          usdSendChainAcceptsAddress(
              'base', bareRecipientAddress('bitcoin:$_btc')),
          isFalse);
      // A Spark address into an EVM recipient: wrong network.
      expect(usdSendChainAcceptsAddress('base', bareRecipientAddress(_spark)),
          isFalse);
    });
  });

  group("bareCrossChainRecipient (the bitcoin send's Paste and Scan)", () {
    test('an ethereum:0x…@8453 code becomes the bare address', () {
      expect(bareCrossChainRecipient('ethereum:$_evm@8453'), _evm);
      expect(bareCrossChainRecipient(' ethereum:$_evm@8453?value=0 '), _evm);
      expect(
          usdSendChainAcceptsAddress(
              'base', bareCrossChainRecipient('ethereum:$_evm@8453')),
          isTrue);
    });

    test('a token-transfer code pays its address param, not the token', () {
      expect(
          bareCrossChainRecipient(
              'ethereum:$_usdcContract@8453/transfer?address=$_evm&uint256=1e6'),
          _evm);
    });

    test('solana: and tron: codes are reduced too', () {
      expect(bareCrossChainRecipient('tron:$_tron?amount=1'), _tron);
      expect(
          bareCrossChainRecipient(
              'solana:7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU?amount=1'),
          '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU');
    });

    test('a BIP21 with an amount is passed on unchanged', () {
      const bip21 = 'bitcoin:$_btc?amount=0.001&label=Coffee';
      expect(bareCrossChainRecipient(bip21), bip21);
      const unified = 'bitcoin:$_btc?amount=0.001&lightning=lnbc10u1pexample';
      expect(bareCrossChainRecipient(unified), unified);
    });

    test('lightning:, spark: and bare payloads are passed on whole', () {
      const ln = 'lightning:lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwz';
      expect(bareCrossChainRecipient(ln), ln);
      expect(bareCrossChainRecipient('spark:$_spark?amount=5'),
          'spark:$_spark?amount=5');
      expect(bareCrossChainRecipient(_spark), _spark);
      expect(bareCrossChainRecipient('lnbc1pvjluezpp5qqqsyqcyq5'),
          'lnbc1pvjluezpp5qqqsyqcyq5');
      expect(bareCrossChainRecipient('alice@getalby.com'), 'alice@getalby.com');
      expect(bareCrossChainRecipient(_btc), _btc);
    });
  });

  testWidgets(
      'Scan chip opens the scanner sheet in recipient mode and hands back '
      'its value; closing it hands back nothing', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final l10n = AppLocalizationsEn();
    final cameras = FakeScannerCameras();
    String? received;
    var returned = false;

    await tester.pumpWidget(ProviderScope(
      overrides: [cameras.override],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Row(children: [
                KutePasteChip(onPressed: () {}),
                KuteScanChip(onPressed: () async {
                  received = await scanRecipientRaw(context);
                  returned = true;
                }),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(l10n.paste), findsOneWidget);
    expect(find.text(l10n.scan), findsOneWidget);

    // Closed without a code: nothing comes back.
    await tester.tap(find.text(l10n.scan));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsOneWidget);
    expect(tester.widget<ScannerSheet>(find.byType(ScannerSheet)).mode,
        ScannerMode.recipient);
    expect(cameras.last.multiPart, isFalse);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(returned, isTrue);
    expect(received, isNull);
    expect(cameras.last.disposed, isTrue);

    // A code comes back trimmed.
    returned = false;
    await tester.tap(find.text(l10n.scan));
    await tester.pumpAndSettle();
    cameras.last.scan('  spark:$_spark  ');
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(returned, isTrue);
    expect(received, 'spark:$_spark');
    expect(bareRecipientAddress(received!), _spark);
    expect(cameras.last.disposed, isTrue);
  });

  testWidgets(
      'the multi-part scanner joins nothing for a plain code and hands it '
      'back as read', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final cameras = FakeScannerCameras();
    String? received;

    await tester.pumpWidget(ProviderScope(
      overrides: [cameras.override],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    received = await showScannerSheet(context, multiPart: true),
                child: const Text('scan'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    expect(
        ModalRoute.of(tester.element(find.byType(ScannerSheet)))!.settings.name,
        kMultiPartScannerRouteName);
    expect(cameras.last.multiPart, isTrue);
    cameras.last.scan(_spark);
    await tester.pumpAndSettle();
    expect(find.byType(ScannerSheet), findsNothing);
    expect(received, _spark);
    expect(cameras.last.disposed, isTrue);
  });
}
