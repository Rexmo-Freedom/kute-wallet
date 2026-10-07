import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final family in ['Inter', 'Inter_regular', 'Inter_600', 'Inter_700']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
      await loader.load();
    }
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('receipt remains readable at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var haptics = 0;
      KuteConfirmation.debugFeedbackOverride = () async {
        haptics++;
      };
      addTearDown(() => KuteConfirmation.debugFeedbackOverride = null);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: buildLightTheme().copyWith(
              splashFactory: NoSplash.splashFactory,
              textTheme: buildLightTheme().textTheme.apply(fontFamily: 'Inter'),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: KuteConfirmation(
                message: 'Prediction won',
                celebrate: true,
                buttonText: 'My bets',
                onDone: () {},
                receipt: const TradeReceipt(
                  title: 'Portugal to win the final',
                  subtitle: 'Yes',
                  rows: {
                    'Settlement payout': r'$18.00',
                    'Position cost basis': r'$10.00',
                    'Return less cost basis': r'$8.00',
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(r'$18.00'), findsOneWidget);
      expect(haptics, 1);
    });
  }

  testWidgets('neutral results do not fire success feedback', (tester) async {
    var haptics = 0;
    KuteConfirmation.debugFeedbackOverride = () async {
      haptics++;
    };
    addTearDown(() => KuteConfirmation.debugFeedbackOverride = null);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: KuteConfirmation(
            message: 'Prediction lost',
            success: false,
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(haptics, 0);
    expect(find.byType(KuteCheckMark), findsNothing);
  });
}
