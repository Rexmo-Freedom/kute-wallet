import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/wallets_screen.dart';
import 'package:kute/theme/app_theme.dart';

// Public addresses of the abandon x11 about vector. Never fund them.
const _eoa = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
const _pm = '0x1111111111111111111111111111111111112222';

class _Settings extends StateNotifier<Settings> implements SettingsModel {
  _Settings(List<WalletConfig> wallets)
      : super(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'default',
            reviewDone: true,
            activeWalletId: wallets.first.id,
            wallets: wallets));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizationsEn();

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> mount(WidgetTester tester,
      {String? eoa,
      String? pm,
      EvmDerivationVersion version = EvmDerivationVersion.legacySha256}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _Settings([
              WalletConfig(
                  id: 'a',
                  name: 'Spending Wallet',
                  evmDerivationVersion: version),
              WalletConfig(
                  id: 'b',
                  name: 'Cold',
                  sparkEnabled: false,
                  isHardware: true,
                  isWatchOnly: true),
            ])),
        hyperliquidAddressProvider.overrideWith((ref) async => eoa),
        polymarketDepositWalletAddressProvider
            .overrideWith((ref, walletId) async => pm),
      ],
      child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const WalletsScreen(),
              )),
    ));
    await tester.pump();
    await tester.pump();
  }

  Iterable<String> texts() => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((t) => t.isNotEmpty);

  testWidgets('rows carry no address, key hint or type caption',
      (tester) async {
    await mount(tester, eoa: _eoa, pm: _pm);

    expect(find.text('Spending Wallet'), findsOneWidget);
    expect(find.text(l10n.walletsEvmKey), findsOneWidget);
    expect(find.text(l10n.walletsInvestingAccount), findsOneWidget);
    expect(find.text(l10n.walletsPredictionsWallet), findsOneWidget);

    // The one caption allowed: which key format the wallet uses.
    final formatCaptions = {
      l10n.walletsEvmFormatStandard,
      l10n.walletsEvmFormatLegacy,
    };
    for (final text in texts()) {
      // No full or shortened address of either account.
      expect(text, isNot(contains('0x')), reason: text);
      expect(text.toLowerCase(), isNot(contains('eda94')), reason: text);
      expect(text, isNot(contains('2222')), reason: text);
      if (formatCaptions.contains(text)) continue;
      expect(text, isNot(contains('0x')), reason: text);
      expect(text.toLowerCase(), isNot(contains('eda94')), reason: text);
      expect(text, isNot(contains('2222')), reason: text);
      // No mechanism captions about keys next to the rows.
      expect(text, isNot(contains('bitcoin keys')), reason: text);
      expect(text, isNot(contains('recovery phrase')), reason: text);
      expect(text, isNot(contains('Hyperliquid')), reason: text);
      expect(text, isNot(contains('Polymarket')), reason: text);
    }
    // The wallet type caption under each wallet is gone too.
    expect(find.text(l10n.walletTypeKute), findsNothing);
    expect(find.text(l10n.walletTypeViewOnly), findsNothing);
    expect(find.text(l10n.walletTypeHardware), findsNothing);
    expect(find.text(l10n.walletsEvmNotSetUp), findsNothing);
  });

  testWidgets('an account not set up yet still says so', (tester) async {
    await mount(tester);
    expect(find.text(l10n.walletsEvmNotSetUp), findsNWidgets(2));
  });

  // Hex runs of 6+ characters or anything shaped like an address or key.
  final hexish = RegExp(r'0x|[0-9a-fA-F]{6,}');

  testWidgets('a legacy-format wallet says legacy format',
      (tester) async {
    await mount(tester, eoa: _eoa, pm: _pm);
    final caption = find.descendant(
        of: find.byKey(const ValueKey('wallets-evm-key-a')),
        matching: find.text(l10n.walletsEvmFormatLegacy));
    expect(caption, findsOneWidget);
    expect(find.text(l10n.walletsEvmFormatStandard), findsNothing);
    expect(l10n.walletsEvmFormatLegacy, isNot(matches(hexish)));
    expect(l10n.walletsEvmFormatLegacy, isNot(contains(_eoa)));
  });

  testWidgets('a standard-format wallet says standard format',
      (tester) async {
    await mount(tester,
        eoa: _eoa, pm: _pm, version: EvmDerivationVersion.standardBip39);
    final caption = find.descendant(
        of: find.byKey(const ValueKey('wallets-evm-key-a')),
        matching: find.text(l10n.walletsEvmFormatStandard));
    expect(caption, findsOneWidget);
    expect(find.text(l10n.walletsEvmFormatLegacy), findsNothing);
    expect(l10n.walletsEvmFormatStandard, isNot(matches(hexish)));
    expect(l10n.walletsEvmFormatStandard, isNot(contains(_eoa)));
  });

  testWidgets('no locale puts hex or an address in the format captions',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final t = lookupAppLocalizations(locale);
      for (final caption in [
        t.walletsEvmFormatStandard,
        t.walletsEvmFormatLegacy
      ]) {
        expect(caption, isNot(matches(hexish)), reason: '$locale: $caption');
      }
    }
  });
}
