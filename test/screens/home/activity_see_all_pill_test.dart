// The Bitcoin home's Activity pill: selected, it reads "See all" with the
// arrow and a tap opens the full list; on Balance it reads Activity again
// (founder, 1 November 2026).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  test('the label rule: See all only when selected and a list can open', () {
    expect(activityPillSeesAll(selected: true, hasSeeAll: true), isTrue);
    expect(activityPillSeesAll(selected: false, hasSeeAll: true), isFalse);
    expect(activityPillSeesAll(selected: true, hasSeeAll: false), isFalse);
  });

  testWidgets('selected Activity reads See all; Balance turns it back',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    final settings = Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
      activeWalletId: 'spending',
      balancePrivacy: 0,
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => SettingsModel(settings)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: const Locale('en'),
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeAnalyticsWidget(
                surface: 'home',
                activityAndBalanceOnly: true,
                activityChild: const Text('the rows'),
                valuationChild: const Text('the chart'),
                onSeeAllActivity: () => opened++,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // Activity is the landing pill: it names what a second tap does.
    expect(find.text('the rows'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

    await tester.tap(find.text('See all'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, 1);
    expect(find.text('the rows'), findsOneWidget);

    // On Balance the pill is Activity again, and a tap only selects it.
    await tester.tap(find.text('Balance'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('the chart'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, 1);
    expect(find.text('the rows'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
