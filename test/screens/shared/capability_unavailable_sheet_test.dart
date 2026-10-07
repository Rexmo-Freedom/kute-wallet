// The one "unavailable" sheet a blocked Bet, order, Deposit or Add money
// opens: a region block reads "Not available in your region" over the
// network / VPN sentence; anything else reads the generic title over the
// policy's own reason. Never a reason code, and one "Got it" closes it.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _pt = lookupAppLocalizations(const Locale('pt'));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<BuildContext> pumpHost(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext captured;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          captured = context;
          return const Scaffold();
        }),
      ),
    ));
    return captured;
  }

  testWidgets('region block: region title and the VPN sentence',
      (tester) async {
    final context = await pumpHost(tester);
    const decision =
        CapabilityDecision(allowed: false, reason: 'country_blocked');
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();

    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    // Built like every other sheet: the shared container and header.
    expect(find.byType(AppBottomSheetContainer), findsOneWidget);
    expect(find.byType(AppBottomSheetHeader), findsOneWidget);
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.capabilityRegionRestricted), findsOneWidget);
    expect(_en.capabilityRegionRestricted, contains('VPN'));
    expect(find.text(_en.gateUnavailableTitle), findsNothing);
    expect(find.textContaining('country_blocked'), findsNothing);

    await tester.tap(find.text(_en.gotIt));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic block: generic title and the generic reason',
      (tester) async {
    final context = await pumpHost(tester);
    const decision = CapabilityDecision(allowed: false, reason: 'switched_off');
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();

    expect(find.text(_en.gateUnavailableTitle), findsOneWidget);
    expect(find.text(_en.capabilityUnavailable), findsOneWidget);
    expect(find.text(_en.capabilityRegionTitle), findsNothing);
    expect(find.text(_en.capabilityRegionRestricted), findsNothing);
    expect(find.textContaining('switched_off'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caller title replaces the generic one, never the region one',
      (tester) async {
    final context = await pumpHost(tester);
    showCapabilityDecisionSheet(
        context, const CapabilityDecision(allowed: false, reason: 'off'),
        title: _en.gatePredictionsUnavailable);
    await tester.pumpAndSettle();
    expect(find.text(_en.gatePredictionsUnavailable), findsOneWidget);
    await tester.tap(find.text(_en.gotIt));
    await tester.pumpAndSettle();

    showCapabilityDecisionSheet(context,
        const CapabilityDecision(allowed: false, reason: 'country_not_allowed'),
        title: _en.gatePredictionsUnavailable);
    await tester.pumpAndSettle();
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.gatePredictionsUnavailable), findsNothing);
  });

  testWidgets('the venue\'s own region answer reads as a region block',
      (tester) async {
    final context = await pumpHost(tester);
    bool? shown;
    showCapabilityErrorSheet(
            context,
            const ProviderAvailabilityException(ProviderAvailability(
                InvestmentProvider.polymarket,
                ProviderAvailabilityStatus.restricted)))
        .then((value) => shown = value);
    await tester.pumpAndSettle();
    expect(find.text(_en.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_en.providerRegionRestricted('Polymarket')),
        findsOneWidget);
    await tester.tap(find.text(_en.gotIt));
    await tester.pumpAndSettle();
    expect(shown, isTrue);
  });

  testWidgets('a second tap never stacks another sheet', (tester) async {
    final context = await pumpHost(tester);
    const decision =
        CapabilityDecision(allowed: false, reason: 'country_blocked');
    showCapabilityDecisionSheet(context, decision);
    showCapabilityDecisionSheet(context, decision);
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    await tester.tap(find.text(_en.gotIt));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityUnavailableSheet), findsNothing);
  });

  testWidgets('European Portuguese copy', (tester) async {
    final context = await pumpHost(tester, locale: const Locale('pt'));
    showCapabilityDecisionSheet(context,
        const CapabilityDecision(allowed: false, reason: 'country_blocked'));
    await tester.pumpAndSettle();
    expect(find.text(_pt.capabilityRegionTitle), findsOneWidget);
    expect(find.text(_pt.capabilityRegionRestricted), findsOneWidget);
    expect(find.text(_pt.gotIt), findsOneWidget);
  });
}
