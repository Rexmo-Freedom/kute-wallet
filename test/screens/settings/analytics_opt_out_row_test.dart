import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/theme/app_theme.dart';

/// The analytics switch is hidden behind [showAnalyticsOptOut]: while the
/// flag is off the Settings screen must not build the row at all.
void main() {
  final l10n = AppLocalizationsEn();

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('flag off: no analytics row in Settings', (tester) async {
    expect(showAnalyticsOptOut, isFalse,
        reason: 'the opt-out ships hidden; flip this test when it ships');

    tester.view.physicalSize = const Size(430, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Settings stay loading: the provider falls back to its defaults.
    final never = Completer<settings_model.Settings>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWith((ref) => never.future),
        biometricsAvailableProvider.overrideWith((ref) async => false),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Settings(),
        ),
      ),
    ));
    await tester.pump();

    // The Security card rendered, so the absence below is meaningful.
    expect(find.text(l10n.security), findsOneWidget);
    expect(find.text(l10n.autoLock), findsOneWidget);
    expect(find.text(l10n.settingsShareUsageAnalytics), findsNothing);
    expect(find.text(l10n.settingsShareUsageAnalyticsSubtitle), findsNothing);
  });
}
