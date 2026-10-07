// The Settings option pickers (language, display currency, Bitcoin unit,
// auto-lock) sit on the app's shared sheet chrome: the standard header
// with its title and close X, AppBottomSheetListTile rows with the current
// choice selected, and one scrolling list that never overflows.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _l10n = AppLocalizationsEn();

settings_model.Settings _settings({String language = 'sv'}) =>
    settings_model.Settings(
      currency: 'EUR',
      language: language,
      btcFormat: 'sats',
      backup: true,
      bitcoinElectrumNode: 'electrum.blockstream.info:50002',
      nodeType: 'Blockstream',
      balancePrivacy: 1,
      biometricsEnabled: false,
      reviewDone: false,
      fullAccount: false,
      kycCompleted: false,
      country: null,
      wallets: const [],
      activeWalletId: null,
      isPremium: false,
    );

void main() {
  setUpAll(() {
    // A pick writes the choice to the settings box.
    Hive.init(Directory.systemTemp.createTempSync('kute_pickers').path);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester,
      {String? action}) async {
    // A phone-sized view, so the long lists have to scroll.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      initialSettingsProvider.overrideWith((ref) async => _settings()),
      biometricsAvailableProvider.overrideWith((ref) async => false),
      appVersionLabelProvider.overrideWith((ref) async => '2.1.0 (78)'),
    ]);
    addTearDown(container.dispose);
    await container.read(initialSettingsProvider.future);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => Settings(initialActionKey: action)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  Finder sheetTile(String title) => find.ancestor(
      of: find.text(title), matching: find.byType(AppBottomSheetListTile));

  testWidgets(
      'language: header with close, native names, the current one '
      'selected and scrolled into view; a pick closes the sheet',
      (tester) async {
    await pumpSettings(tester, action: 'language');

    expect(find.byType(AppBottomSheetHeader), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byType(AppBottomSheetListTile), findsWidgets);
    // Svenska is near the end of the list: the sheet opens on it.
    final selected =
        tester.widget<AppBottomSheetListTile>(sheetTile('Svenska'));
    expect(selected.isSelected, isTrue);
    expect(sheetTile('Svenska').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Dansk'), -200,
        scrollable: find.descendant(
            of: find.byType(AppBottomSheetContainer),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text('Dansk'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBottomSheetHeader), findsNothing);
  });

  testWidgets('display currency: every currency reachable, no overflow',
      (tester) async {
    await pumpSettings(tester, action: 'currency');
    expect(find.text(_l10n.displayCurrency), findsWidgets);
    expect(tester.widget<AppBottomSheetListTile>(sheetTile('EUR')).isSelected,
        isTrue);
    await tester.scrollUntilVisible(find.text('RON'), 200,
        scrollable: find.descendant(
            of: find.byType(AppBottomSheetContainer),
            matching: find.byType(Scrollable)));
    expect(find.text('RON').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bitcoin unit: the current unit selected; close dismisses',
      (tester) async {
    final container = await pumpSettings(tester, action: 'bitcoin_unit');
    expect(
        tester
            .widget<AppBottomSheetListTile>(sheetTile(_l10n.accountSats))
            .isSelected,
        isTrue);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBottomSheetHeader), findsNothing);
    expect(container.read(settingsProvider).btcFormat, 'sats');
  });
}
