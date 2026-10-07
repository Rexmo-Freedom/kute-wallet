import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/pay/components/watch_only_screen.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/helpers/extension.dart';

const _address = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _other = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'default',
          reviewDone: true,
          activeWalletId: 'wallet-1',
          wallets: [WalletConfig(id: 'wallet-1', name: 'Hardware')],
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'the signing review keeps the full recipient after shared state changes',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => _Settings()),
    ]);
    addTearDown(container.dispose);
    final sendSubscription = container.listen(sendTxProvider, (_, __) {});
    addTearDown(sendSubscription.close);
    final notifier = container.read(sendTxProvider.notifier);
    notifier.updateAddress(_address);
    notifier.updateAmount(50000);

    Widget screen() => UncontrolledProviderScope(
          container: container,
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              theme: buildLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                  body: WatchOnlySigningScreen(
                psbtBase64: 'cHNidP8A',
                walletType: 'generic',
                embedded: true,
              )),
            ),
          ),
        );

    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.text(_address), findsOneWidget);
    expect(
        find.text('${50000.toFormattedString('sats')} sats'), findsOneWidget);

    notifier.updateAddress(_other);
    notifier.updateAmount(90000);
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.text(_address), findsOneWidget);
    expect(find.text(_other), findsNothing);
    expect(
        find.text('${50000.toFormattedString('sats')} sats'), findsOneWidget);
    expect(find.text('${90000.toFormattedString('sats')} sats'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
