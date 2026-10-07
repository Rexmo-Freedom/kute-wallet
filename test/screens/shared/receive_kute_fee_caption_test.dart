import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/theme/app_theme.dart';

/// The fee line beside a reusable deposit address shows the rate the
/// address's own backend terms charge (`kuteFeePolicy.appFeeBps`, the
/// cross_chain_deposit rule with the referral discount already taken off),
/// and nothing at all when that rate is not known.
void main() {
  final l10n = AppLocalizationsEn();

  // What the backend attaches to an address minted under a 50 bps
  // cross_chain_deposit rule for a referred account with a 15 bps perk.
  const discountedPolicy = {
    'revision': 7,
    'credentialVersion': 'v1',
    'purpose': 'cross_chain_deposit',
    'appFeeBps': 35,
    'affiliateId': 'kute',
    'referralDiscountBps': 15,
  };

  Map<String, dynamic> addressJson(Object? policy) => {
        'accumulationAddressId': 'acc_1',
        'sourceChain': 'ethereum',
        'sourceAsset': 'USDC',
        'destinationAsset': 'BTC',
        'recipientSparkAddress': 'sp1test',
        'depositAddress': '0xabc',
        'enabled': true,
        'createdAt': '2026-10-07T00:00:00Z',
        if (policy != null) 'kuteFeePolicy': policy,
      };

  group('rate from the address terms', () {
    test('accumulation address: the charged rule, discount applied', () {
      final address =
          OrchestraAccumulationAddress.fromJson(addressJson(discountedPolicy));
      expect(address.kuteFeeBps, 35);
    });

    test('standing address: the charged rule, discount applied', () {
      const record = StandingDepositRecord(
          walletId: 'w',
          label: 'l',
          recipient: 'sp1test',
          asset: 'USDB',
          revision: 7,
          response: {'kuteFeePolicy': discountedPolicy});
      expect(record.kuteFeeBps, 35);
    });

    test('unknown or no fee: null, never a guess', () {
      expect(OrchestraAccumulationAddress.fromJson(addressJson(null)).kuteFeeBps,
          isNull);
      expect(
          disclosedKuteFeeBps({...discountedPolicy, 'providerDefault': true}),
          isNull);
      expect(disclosedKuteFeeBps({...discountedPolicy, 'appFeeBps': 0}),
          isNull);
      expect(disclosedKuteFeeBps({...discountedPolicy, 'appFeeBps': '35'}),
          isNull);
      expect(disclosedKuteFeeBps({'revision': 7}), isNull);
      expect(
          const StandingDepositRecord(
                  walletId: 'w',
                  label: 'l',
                  recipient: 'sp1test',
                  asset: 'USDB',
                  revision: 7)
              .kuteFeeBps,
          isNull);
    });
  });

  group('caption', () {
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<void> pump(WidgetTester tester, int? bps) =>
        tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ReceiveKuteFeeCaption(bps: bps)),
          ),
        ));

    testWidgets('shows the exact rate the terms charge', (tester) async {
      await pump(tester, disclosedKuteFeeBps(discountedPolicy));
      expect(find.text(l10n.receiveKuteFeeOnArrival('0.35%')), findsOneWidget);
    });

    testWidgets('rate unavailable: nothing on screen', (tester) async {
      await pump(tester, null);
      expect(find.byType(Text), findsNothing);
    });
  });
}
