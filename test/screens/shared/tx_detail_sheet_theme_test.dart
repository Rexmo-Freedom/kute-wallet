// An open Activity detail sheet follows a live light/dark switch: every
// value, not only the labels, takes the new theme's colours. The sheets
// used to read the palette from the row that opened them, once, at tap
// time, so after dark -> light the Date, Value then and Description values
// and the "View on the blockchain" button stayed white on the light sheet.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/tx_fiat_snapshot_service.dart';
import 'package:kute/theme/app_theme.dart';

final _at = DateTime(2026, 10, 20, 17, 1);
const _description = 'Wallet of Satoshi: coffee';

SparkTransaction _lightningSend() => SparkTransaction(
      id: 'ln-send-1',
      timestamp: _at,
      isConfirmed: true,
      details: breez.Payment(
        id: 'ln-send-1',
        paymentType: breez.PaymentType.send,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from(10),
        fees: BigInt.zero,
        timestamp: BigInt.from(_at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.lightning,
        details: breez.PaymentDetails.lightning(
          description: _description,
          invoice: 'lnbc1invoice',
          destinationPubkey: '02pubkey',
          htlcDetails: breez.SparkHtlcDetails(
            paymentHash: 'hash',
            preimage: 'preimage',
            expiryTime: BigInt.zero,
            status: breez.SparkHtlcStatus.preimageShared,
          ),
        ),
      ),
    );

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('tx_sheet_theme');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(TxFiatSnapshotService.boxName);
    TxFiatSnapshotService.recordUsd('ln-send-1', 0.01, 10);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  testWidgets(
      'a Lightning send sheet open across dark -> light recolours its values '
      'and the explorer button', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    late BuildContext opener;
    late WidgetRef openerRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              balancePrivacy: 0,
              biometricsEnabled: false,
              bitcoinElectrumNode: 'localhost',
              nodeType: 'Blockstream',
              reviewDone: false,
              wallets: [WalletConfig(id: 'spending', name: 'Spending')],
              activeWalletId: 'spending',
            ))),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ThemeMode.system,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              opener = context;
              openerRef = ref;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await openTransactionDetails(opener, openerRef, _lightningSend());
    await settle();

    final l10n = AppLocalizations.of(opener);
    final date = activitySheetDate(opener, _at);

    Color? colorOf(Finder f) => tester
        .widget<RichText>(
            find.descendant(of: f, matching: find.byType(RichText)).first)
        .text
        .style
        ?.color;
    Color? textColor(String s) => colorOf(find.text(s));
    Color? buttonLabel() => colorOf(find.text(l10n.activityViewOnBlockchain));
    Color? buttonIcon() => colorOf(find.byIcon(Icons.open_in_new_rounded));

    final dark = buildDarkTheme().extension<AppColorsExtension>()!;
    final light = buildLightTheme().extension<AppColorsExtension>()!;
    expect(light.textPrimary, isNot(dark.textPrimary));

    expect(textColor(date), dark.textPrimary);
    expect(textColor(r'$0.01'), dark.textPrimary);
    expect(textColor(_description), dark.textPrimary);
    expect(buttonLabel(), dark.textPrimary);
    expect(buttonIcon(), dark.textPrimary);

    // The appearance flips while the sheet stays open.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await settle();

    expect(textColor(date), light.textPrimary, reason: 'Date value');
    expect(textColor(r'$0.01'), light.textPrimary, reason: 'Value then');
    expect(textColor(_description), light.textPrimary,
        reason: 'Description value');
    expect(buttonLabel(), light.textPrimary, reason: 'explorer label');
    expect(buttonIcon(), light.textPrimary, reason: 'explorer icon');
    final border = tester
        .widget<OutlinedButton>(find.byType(OutlinedButton))
        .style!
        .side!
        .resolve({});
    expect(border?.color, light.border, reason: 'explorer border');
  });
}
